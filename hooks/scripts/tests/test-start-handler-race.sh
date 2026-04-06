#!/usr/bin/env bash
# test-start-handler-race.sh — Tests for F14 start handler refactor
#
# Verifies that the 'start' event handler uses regress_to_phase("analysis", --force)
# instead of rm+state_init, and that stale .agent-stack entries are cleared before
# the regression call so SC-REGRESS-01 does not trigger.
#
#   1. Fresh project (no state.json) + start event with analysis agent
#      → state.json created with currentPhase=analysis
#   2. phase=done + start event with analysis agent
#      → regress_to_phase called, currentPhase=analysis, currentTier=null
#   3. phase=idle + start event with analysis agent
#      → same as test 2 (currentPhase=analysis)
#   4. phase=worker + start event with analysis agent
#      → no reset (mid-pipeline), currentPhase unchanged
#   5. stale .agent-stack entries + phase=idle
#      → .agent-stack cleared before regress, regress succeeds (SC-REGRESS-01 not triggered)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_LOGGER="$SCRIPT_DIR/../agent-logger.sh"

PASS=0
FAIL=0
TOTAL=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_eq() {
  local test_name="$1"
  local expected="$2"
  local actual="$3"
  TOTAL=$((TOTAL + 1))
  if [ "$expected" = "$actual" ]; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name (expected=$expected)"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (expected='$expected', actual='$actual')"
  fi
}

assert_true() {
  local test_name="$1"
  local actual="$2"
  assert_eq "$test_name" "true" "$actual"
}

assert_false() {
  local test_name="$1"
  local actual="$2"
  assert_eq "$test_name" "false" "$actual"
}

# Read a dot-notation field from state.json
read_state_field() {
  local dir="$1"
  local field="$2"
  python3 -c "
import json
try:
    with open('$dir/.baton/state.json') as f:
        d = json.load(f)
    keys = '$field'.split('.')
    val = d
    for k in keys:
        if isinstance(val, dict) and k in val:
            val = val[k]
        else:
            print('null')
            exit(0)
    if isinstance(val, bool):
        print('true' if val else 'false')
    elif val is None:
        print('null')
    elif isinstance(val, (dict, list)):
        print(json.dumps(val))
    else:
        print(val)
except FileNotFoundError:
    print('missing')
"
}

# Build SubagentStart JSON for an analysis agent
make_analysis_start_json() {
  python3 -c "
import json
print(json.dumps({
    'hook_event_name': 'SubagentStart',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:analysis-agent',
    'agent_name': 'claude-baton:analysis-agent',
    'tool_input': {'description': 'analysis-agent: detect stack and complexity'}
}))
"
}

# Run agent-logger start with the given JSON payload
run_start() {
  local baton_root="$1"
  local json_data="$2"
  local slow_regress="${3:-}"

  local exit_code=0
  if [ -n "$slow_regress" ]; then
    echo "$json_data" \
      | BATON_ROOT="$baton_root" SLOW_REGRESS="$slow_regress" \
        bash "$AGENT_LOGGER" start > /dev/null 2>&1 || exit_code=$?
  else
    echo "$json_data" \
      | BATON_ROOT="$baton_root" \
        bash "$AGENT_LOGGER" start > /dev/null 2>&1 || exit_code=$?
  fi
  return 0  # hook exit codes do not propagate test assertions
}

# Initialize state.json with given phase
init_state_with_phase() {
  local dir="$1"
  local phase="$2"
  local tier="${3:-2}"
  python3 - "$phase" "$tier" <<'PYEOF'
import json, sys, os

phase = sys.argv[1]
tier = sys.argv[2]
tier_val = int(tier) if tier != 'null' else None

state = {
    'version': 3,
    'currentTier': tier_val,
    'currentPhase': phase,
    'securityHalt': False,
    'phaseFlags': {
        'issueRegistered': True,
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': True,
        'qaIntegrationPassed': True,
        'reviewCompleted': True,
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': ['r1', 'r2', 'r3']},
    'workerTracker': {'expected': 1, 'doneCount': 1},
    'qaRetryCount': {},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [],
    'artifactStale': {},
    'lastCommitAttemptCount': 0,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}

state_dir = os.path.join(os.environ['BATON_ROOT'], '.baton')
os.makedirs(state_dir, exist_ok=True)
with open(os.path.join(state_dir, 'state.json'), 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
PYEOF
}

echo "=== F14 Start Handler Refactor Tests ==="
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 1: Fresh project (no state.json) + analysis agent start
#         → state.json created with currentPhase=analysis
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 1: Fresh project (no state.json) + analysis start → currentPhase=analysis ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
# Do NOT create state.json — fresh project scenario
json=$(make_analysis_start_json)
run_start "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
assert_eq "1a: currentPhase=analysis on fresh project start" "analysis" "$actual_phase"

# Verify state.json exists and is valid JSON
valid_json="false"
if python3 -c "import json; json.load(open('$T/.baton/state.json'))" 2>/dev/null; then
  valid_json="true"
fi
assert_true "1b: state.json is valid JSON after fresh start" "$valid_json"

rm -rf "$T"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 2: phase=done + analysis agent start
#         → regress_to_phase called, currentPhase=analysis, currentTier=null
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 2: phase=done + analysis start → currentPhase=analysis, currentTier=null ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_state_with_phase "$T" "done" 2
json=$(make_analysis_start_json)
run_start "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_tier=$(read_state_field "$T" "currentTier")

assert_eq "2a: currentPhase=analysis after done→analysis regression" "analysis" "$actual_phase"
assert_eq "2b: currentTier=null after analysis regression (tier reset)" "null" "$actual_tier"

rm -rf "$T"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 3: phase=idle + analysis agent start
#         → currentPhase=analysis
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 3: phase=idle + analysis start → currentPhase=analysis ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_state_with_phase "$T" "idle" "null"
json=$(make_analysis_start_json)
run_start "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
assert_eq "3a: currentPhase=analysis after idle→analysis regression" "analysis" "$actual_phase"

rm -rf "$T"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 4: phase=worker + analysis agent start
#         → no reset (mid-pipeline), currentPhase remains worker
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 4: phase=worker + analysis start → no reset, currentPhase=worker ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_state_with_phase "$T" "worker" 2
json=$(make_analysis_start_json)
run_start "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
assert_eq "4a: currentPhase=worker (no reset mid-pipeline)" "worker" "$actual_phase"

rm -rf "$T"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 5: Stale .agent-stack + phase=idle
#         → .agent-stack cleared before regress, regress succeeds
#           (no SC-REGRESS-01 refusal)
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 5: stale .agent-stack + phase=idle → stack cleared, regress succeeds ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_state_with_phase "$T" "idle" "null"

# Populate stale .agent-stack entries from a prior pipeline
echo "2026-04-04T10:00:00Z|claude-baton:worker-agent" > "$T/.baton/logs/.agent-stack"
echo "2026-04-04T10:01:00Z|claude-baton:qa-unit"     >> "$T/.baton/logs/.agent-stack"

json=$(make_analysis_start_json)
run_start "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")

# Regression must succeed (not blocked by SC-REGRESS-01)
assert_eq "5a: currentPhase=analysis despite stale .agent-stack (cleared before regress)" "analysis" "$actual_phase"

# After regress, .agent-stack should contain only the new analysis agent
# (appended at end of start handler) — so exactly 1 entry
stack_count=0
if [ -f "$T/.baton/logs/.agent-stack" ]; then
  stack_count=$(wc -l < "$T/.baton/logs/.agent-stack" | tr -d ' ')
fi
assert_eq "5b: .agent-stack has exactly 1 entry (new analysis agent appended post-regress)" "1" "$stack_count"

rm -rf "$T"
echo ""

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
echo "=== Summary ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}SOME TESTS FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
fi
