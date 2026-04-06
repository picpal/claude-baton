#!/usr/bin/env bash
# test-regress-to-phase.sh — Tests for regress_to_phase() in regress-to-phase.sh
#
# Verifies the phase regression engine:
#   1. Guard tests (subagent context, securityHalt, invalid target, Tier 1 refuse,
#      deep regression --force requirement, done state guard)
#   2. Shallow regression (review->worker, qa->worker)
#   3. Deep regression with --force (review->planning, review->analysis)
#   4. Tier 1 special case (worker target reactivates skipped flags)
#   5. Atomic write (state.json never in partial state)
#   6. Artifact invalidation (artifactStale marks correct files)
#   7. regressionHistory (entry appended with correct fields)
#   8. reworkStatus (active=true, attemptCount incremented)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REGRESS_SCRIPT="$SCRIPT_DIR/../regress-to-phase.sh"
STATE_MANAGER="$SCRIPT_DIR/../state-manager.sh"

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
    echo -e "${RED}FAIL${NC}: $test_name (expected=$expected, actual=$actual)"
  fi
}

assert_true() {
  assert_eq "$1" "true" "$2"
}

assert_false() {
  assert_eq "$1" "false" "$2"
}

# Helper: read a field from state.json
read_state_field() {
  local dir="$1"
  local field="$2"
  python3 -c "
import json
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
"
}

# Helper: write a fully-populated state.json for regression tests
# Defaults represent a Tier 2 pipeline at the review phase, all flags true.
write_test_state() {
  local dir="$1"
  local tier="${2:-2}"
  local current_phase="${3:-review}"
  local security_halt="${4:-false}"
  # Pre-populated trackers and flags simulate a fully-completed pipeline
  python3 - <<PYEOF
import json
state = {
    'version': 3,
    'currentTier': $tier,
    'currentPhase': '$current_phase',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': True,
        'qaIntegrationPassed': True,
        'reviewCompleted': True,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': ['Security Guardian', 'Quality Inspector', 'TDD Enforcer']},
    'workerTracker': {'expected': 2, 'doneCount': 2},
    'qaRetryCount': {'task-01': 1},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [],
    'artifactStale': {},
    'lastCommitAttemptCount': 0,
    'securityHalt': $( [ "$security_halt" = "true" ] && echo "True" || echo "False" ),
    'lastSafeTag': None,
    'issueNumber': 42,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
with open('$dir/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
PYEOF
}

# Helper: invoke regress_to_phase via the new script
run_regress() {
  local baton_root="$1"
  local target="$2"
  local reason="${3:-test reason}"
  local force_flag="${4:-}"
  local exit_code=0
  BATON_ROOT="$baton_root" bash -c "
    source '$REGRESS_SCRIPT'
    regress_to_phase '$target' '$reason' $force_flag
  " > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

echo "=== regress_to_phase() Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: Guard tests
# ─────────────────────────────────────────────────
echo "--- Test Group 1: Guards ---"

# 1a: Empty target -> exit 1 (invalid)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase '' 'no target'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1a: empty target -> exit 1" "1" "$exit_code"
rm -rf "$TEST_ROOT"

# 1b: Invalid target -> exit 1
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'nonexistent' 'bad'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1b: invalid phase 'nonexistent' -> exit 1" "1" "$exit_code"
rm -rf "$TEST_ROOT"

# 1c: SC-REGRESS-01 - subagent active (.agent-stack non-empty) -> exit 4
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
echo "2026-04-05T00:00:00Z|claude-baton:worker-agent" > "$TEST_ROOT/.baton/logs/.agent-stack"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'subagent test'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1c: .agent-stack non-empty -> exit 4 (SC-REGRESS-01)" "4" "$exit_code"
rm -rf "$TEST_ROOT"

# 1d: SC-REGRESS-03 - securityHalt=true -> exit 3
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review" "true"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'security test'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1d: securityHalt=true -> exit 3 (SC-REGRESS-03)" "3" "$exit_code"
rm -rf "$TEST_ROOT"

# 1e: Tier 1 refuses 'interview' target -> exit 2
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 1 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'interview' 'tier1 test'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1e: Tier 1 + interview target -> exit 2" "2" "$exit_code"
rm -rf "$TEST_ROOT"

# 1f: Tier 1 refuses 'planning' target -> exit 2
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 1 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'tier1 test'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1f: Tier 1 + planning target -> exit 2" "2" "$exit_code"
rm -rf "$TEST_ROOT"

# 1g: Tier 1 refuses 'taskmgr' target -> exit 2
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 1 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'taskmgr' 'tier1 test'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1g: Tier 1 + taskmgr target -> exit 2" "2" "$exit_code"
rm -rf "$TEST_ROOT"

# 1h: Tier 1 refuses 'review' target -> exit 2
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 1 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'review' 'tier1 test'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1h: Tier 1 + review target -> exit 2" "2" "$exit_code"
rm -rf "$TEST_ROOT"

# 1i: SC-REGRESS-04 - deep regression (depth>1) without --force -> exit 5
# review (7) -> planning (3) is depth 4, requires --force
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'deep test'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1i: deep regression without --force -> exit 5 (SC-REGRESS-04)" "5" "$exit_code"
rm -rf "$TEST_ROOT"

# 1j: regressionPending recorded after deep-regression refusal
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'deep test'
" > /dev/null 2>&1 || true
actual=$(read_state_field "$TEST_ROOT" "regressionPending.target")
assert_eq "1j: deep regression refusal records regressionPending.target=planning" "planning" "$actual"
rm -rf "$TEST_ROOT"

# 1k: Done state guard - currentPhase=done + target!=analysis -> exit 6
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "done"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'after done'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1k: currentPhase=done + target=worker -> exit 6" "6" "$exit_code"
rm -rf "$TEST_ROOT"

# 1l: Done state guard - currentPhase=done + target=analysis -> allowed (exit 0)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "done"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'analysis' 'new pipeline' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "1l: currentPhase=done + target=analysis (--force) -> exit 0" "0" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 2: Shallow regression (review->worker, qa->worker)
# ─────────────────────────────────────────────────
echo "--- Test Group 2: Shallow regression ---"

# 2a: review (depth 1 to qa) -> qa, no force needed
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "qa rerun"
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_qa_int=$(read_state_field "$TEST_ROOT" "phaseFlags.qaIntegrationPassed")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_planning=$(read_state_field "$TEST_ROOT" "phaseFlags.planningCompleted")
assert_false "2a: qa target -> qaUnitPassed=false" "$actual_qa_unit"
assert_false "2a: qa target -> qaIntegrationPassed=false" "$actual_qa_int"
assert_false "2a: qa target -> reviewCompleted=false" "$actual_review"
assert_true "2a: qa target -> workerCompleted preserved (true)" "$actual_worker"
assert_true "2a: qa target -> planningCompleted preserved (true)" "$actual_planning"
rm -rf "$TEST_ROOT"

# 2b: review -> worker (depth 2 from review), needs --force
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "worker" "worker rerun" "--force"
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_qa_int=$(read_state_field "$TEST_ROOT" "phaseFlags.qaIntegrationPassed")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
actual_taskmgr=$(read_state_field "$TEST_ROOT" "phaseFlags.taskMgrCompleted")
actual_done_count=$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")
actual_expected=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
actual_review_completed=$(read_state_field "$TEST_ROOT" "reviewTracker.completed")
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_false "2b: worker target -> workerCompleted=false" "$actual_worker"
assert_false "2b: worker target -> qaUnitPassed=false" "$actual_qa_unit"
assert_false "2b: worker target -> qaIntegrationPassed=false" "$actual_qa_int"
assert_false "2b: worker target -> reviewCompleted=false" "$actual_review"
assert_true "2b: worker target -> taskMgrCompleted preserved (true)" "$actual_taskmgr"
assert_eq "2b: worker target -> workerTracker.doneCount=0" "0" "$actual_done_count"
assert_eq "2b: worker target -> workerTracker.expected=0" "0" "$actual_expected"
assert_eq "2b: worker target -> reviewTracker.completed=[]" "[]" "$actual_review_completed"
assert_eq "2b: worker target -> currentPhase=worker" "worker" "$actual_phase"
rm -rf "$TEST_ROOT"

# 2c: qa->worker (depth 1) does NOT require --force
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "qa"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'depth-1 from qa'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "2c: qa->worker (depth 1) without --force -> exit 0" "0" "$exit_code"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "2c: qa->worker -> currentPhase=worker" "worker" "$actual_phase"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 3: Deep regression with --force
# ─────────────────────────────────────────────────
echo "--- Test Group 3: Deep regression with --force ---"

# 3a: review -> planning (--force)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "planning" "deep planning" "--force"
actual_planning=$(read_state_field "$TEST_ROOT" "phaseFlags.planningCompleted")
actual_taskmgr=$(read_state_field "$TEST_ROOT" "phaseFlags.taskMgrCompleted")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
actual_interview=$(read_state_field "$TEST_ROOT" "phaseFlags.interviewCompleted")
actual_analysis=$(read_state_field "$TEST_ROOT" "phaseFlags.analysisCompleted")
actual_planning_completed=$(read_state_field "$TEST_ROOT" "planningTracker.completed")
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_false "3a: planning target -> planningCompleted=false" "$actual_planning"
assert_false "3a: planning target -> taskMgrCompleted=false" "$actual_taskmgr"
assert_false "3a: planning target -> workerCompleted=false" "$actual_worker"
assert_false "3a: planning target -> reviewCompleted=false" "$actual_review"
assert_true "3a: planning target -> interviewCompleted preserved (true)" "$actual_interview"
assert_true "3a: planning target -> analysisCompleted preserved (true)" "$actual_analysis"
assert_eq "3a: planning target -> planningTracker.completed=[]" "[]" "$actual_planning_completed"
assert_eq "3a: planning target -> currentPhase=planning" "planning" "$actual_phase"
rm -rf "$TEST_ROOT"

# 3b: review -> analysis (--force) - resets currentTier and marks complexity-score stale
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "analysis" "full reset" "--force"
actual_analysis=$(read_state_field "$TEST_ROOT" "phaseFlags.analysisCompleted")
actual_issue=$(read_state_field "$TEST_ROOT" "phaseFlags.issueRegistered")
actual_tier=$(read_state_field "$TEST_ROOT" "currentTier")
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_false "3b: analysis target -> analysisCompleted=false" "$actual_analysis"
assert_true "3b: analysis target -> issueRegistered preserved (true)" "$actual_issue"
assert_eq "3b: analysis target -> currentTier reset to null" "null" "$actual_tier"
assert_eq "3b: analysis target -> currentPhase=analysis" "analysis" "$actual_phase"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 4: Tier 1 special case for worker target
# ─────────────────────────────────────────────────
echo "--- Test Group 4: Tier 1 worker target special case ---"

# 4a: Tier 1 + worker target -> qaIntegrationPassed and reviewCompleted re-set to true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 1 "qa"
run_regress "$TEST_ROOT" "worker" "tier1 worker rerun"
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_qa_int=$(read_state_field "$TEST_ROOT" "phaseFlags.qaIntegrationPassed")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
assert_false "4a: Tier 1 worker target -> workerCompleted=false" "$actual_worker"
assert_false "4a: Tier 1 worker target -> qaUnitPassed=false (will re-run)" "$actual_qa_unit"
assert_true "4a: Tier 1 worker target -> qaIntegrationPassed=true (Tier 1 skips)" "$actual_qa_int"
assert_true "4a: Tier 1 worker target -> reviewCompleted=true (Tier 1 skips)" "$actual_review"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 5: Atomic write
# ─────────────────────────────────────────────────
echo "--- Test Group 5: Atomic write ---"

# 5a: state.json must remain valid JSON after regression (no partial writes)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "worker" "atomic test" "--force"
# Validate JSON parses cleanly
parses_ok=$(python3 -c "
import json
try:
    with open('$TEST_ROOT/.baton/state.json') as f:
        json.load(f)
    print('true')
except Exception:
    print('false')
")
assert_true "5a: state.json remains valid JSON after regression" "$parses_ok"
# Validate no .tmp leftover
leftover_tmp=""
if ls "$TEST_ROOT/.baton"/state.json.* 2>/dev/null | head -1 > /dev/null; then
  leftover_tmp="found"
fi
assert_eq "5a: no leftover .tmp files in .baton/" "" "$leftover_tmp"
rm -rf "$TEST_ROOT"

# 5b: timestamp updated after regression
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
old_ts=$(read_state_field "$TEST_ROOT" "timestamp")
run_regress "$TEST_ROOT" "qa" "ts test"
new_ts=$(read_state_field "$TEST_ROOT" "timestamp")
ts_changed="false"
[ "$old_ts" != "$new_ts" ] && ts_changed="true"
assert_true "5b: timestamp updated after regression" "$ts_changed"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 6: Artifact invalidation
# ─────────────────────────────────────────────────
echo "--- Test Group 6: Artifact invalidation (artifactStale) ---"

# Helper: read a key from artifactStale (keys contain dots, so we look up directly)
read_artifact_stale() {
  local dir="$1"
  local key="$2"
  python3 -c "
import json
with open('$dir/.baton/state.json') as f:
    d = json.load(f)
val = d.get('artifactStale', {}).get('$key')
if val is None:
    print('null')
elif isinstance(val, bool):
    print('true' if val else 'false')
else:
    print(val)
"
}

# 6a: target=analysis -> all 3 artifacts marked stale
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "analysis" "stale test" "--force"
actual_complexity=$(read_artifact_stale "$TEST_ROOT" "complexity-score.md")
actual_plan=$(read_artifact_stale "$TEST_ROOT" "plan.md")
actual_todo=$(read_artifact_stale "$TEST_ROOT" "todo.md")
assert_true "6a: analysis -> artifactStale[complexity-score.md]=true" "$actual_complexity"
assert_true "6a: analysis -> artifactStale[plan.md]=true" "$actual_plan"
assert_true "6a: analysis -> artifactStale[todo.md]=true" "$actual_todo"
rm -rf "$TEST_ROOT"

# 6b: target=planning -> plan.md and todo.md marked stale, complexity-score.md NOT
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "planning" "stale planning" "--force"
actual_plan=$(read_artifact_stale "$TEST_ROOT" "plan.md")
actual_todo=$(read_artifact_stale "$TEST_ROOT" "todo.md")
actual_complexity=$(read_artifact_stale "$TEST_ROOT" "complexity-score.md")
assert_true "6b: planning -> artifactStale[plan.md]=true" "$actual_plan"
assert_true "6b: planning -> artifactStale[todo.md]=true" "$actual_todo"
assert_eq "6b: planning -> artifactStale[complexity-score.md] not set" "null" "$actual_complexity"
rm -rf "$TEST_ROOT"

# 6c: target=taskmgr -> only todo.md marked stale
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "taskmgr" "stale taskmgr" "--force"
actual_todo=$(read_artifact_stale "$TEST_ROOT" "todo.md")
actual_plan=$(read_artifact_stale "$TEST_ROOT" "plan.md")
assert_true "6c: taskmgr -> artifactStale[todo.md]=true" "$actual_todo"
assert_eq "6c: taskmgr -> artifactStale[plan.md] not set" "null" "$actual_plan"
rm -rf "$TEST_ROOT"

# 6d: target=worker -> no artifact changes
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "worker" "no stale" "--force"
actual_stale=$(read_state_field "$TEST_ROOT" "artifactStale")
assert_eq "6d: worker -> artifactStale unchanged ({})" "{}" "$actual_stale"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 7: regressionHistory
# ─────────────────────────────────────────────────
echo "--- Test Group 7: regressionHistory entries ---"

# 7a: After regression, regressionHistory has exactly one entry
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "qa needs rerun"
hist_len=$(python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
print(len(d.get('regressionHistory', [])))
")
assert_eq "7a: regressionHistory has 1 entry after first regression" "1" "$hist_len"

# 7b: regressionHistory entry has fromPhase, toPhase, attemptCount, reason, timestamp
entry_check=$(python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
entry = d['regressionHistory'][0]
required = ['timestamp', 'fromPhase', 'toPhase', 'attemptCount', 'reason']
print('true' if all(k in entry for k in required) else 'false')
")
assert_true "7b: regressionHistory entry has all required fields" "$entry_check"

# 7c: fromPhase=review, toPhase=qa
from_phase=$(python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
print(d['regressionHistory'][0]['fromPhase'])
")
to_phase=$(python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
print(d['regressionHistory'][0]['toPhase'])
")
reason_field=$(python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
print(d['regressionHistory'][0]['reason'])
")
assert_eq "7c: regressionHistory entry fromPhase=review" "review" "$from_phase"
assert_eq "7c: regressionHistory entry toPhase=qa" "qa" "$to_phase"
assert_eq "7c: regressionHistory entry reason='qa needs rerun'" "qa needs rerun" "$reason_field"
rm -rf "$TEST_ROOT"

# 7d: Multiple regressions append entries
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "first"
# Restore review state for second regression
python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
d['currentPhase'] = 'review'
d['phaseFlags']['qaUnitPassed'] = True
d['phaseFlags']['qaIntegrationPassed'] = True
d['phaseFlags']['reviewCompleted'] = True
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
run_regress "$TEST_ROOT" "qa" "second"
hist_len=$(python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
print(len(d['regressionHistory']))
")
assert_eq "7d: two regressions -> regressionHistory has 2 entries" "2" "$hist_len"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 8: reworkStatus
# ─────────────────────────────────────────────────
echo "--- Test Group 8: reworkStatus ---"

# 8a: After regression, reworkStatus.active=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "test"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
assert_true "8a: reworkStatus.active=true after regression" "$actual"
rm -rf "$TEST_ROOT"

# 8b: First regression -> attemptCount=1
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "first attempt"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.attemptCount")
assert_eq "8b: first regression -> attemptCount=1" "1" "$actual"
rm -rf "$TEST_ROOT"

# 8c: hasWarnings reset to false after regression
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
# Pre-set hasWarnings=true
python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
d['reworkStatus']['hasWarnings'] = True
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
run_regress "$TEST_ROOT" "qa" "warnings reset test"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_false "8c: hasWarnings reset to false after regression" "$actual"
rm -rf "$TEST_ROOT"

# 8d: attemptCount carries over: starts at 2 -> regression -> 3
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
python3 -c "
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
d['reworkStatus']['attemptCount'] = 2
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(d, f, indent=2)
"
run_regress "$TEST_ROOT" "qa" "third attempt"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.attemptCount")
assert_eq "8d: attemptCount=2 -> regression -> attemptCount=3" "3" "$actual"
rm -rf "$TEST_ROOT"

# 8e: qaRetryCount NOT reset (history preservation across regressions)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "preserve qa retry"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-01")
assert_eq "8e: qaRetryCount.task-01=1 preserved across regression" "1" "$actual"
rm -rf "$TEST_ROOT"

# 8f: securityHalt NOT reset
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "preserve security"
actual=$(read_state_field "$TEST_ROOT" "securityHalt")
assert_false "8f: securityHalt=false preserved (not reset to true)" "$actual"
rm -rf "$TEST_ROOT"

# 8g: issueRegistered NOT reset by non-issue-register targets
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "analysis" "preserve issue" "--force"
actual=$(read_state_field "$TEST_ROOT" "phaseFlags.issueRegistered")
assert_true "8g: issueRegistered=true preserved across analysis regression" "$actual"
rm -rf "$TEST_ROOT"

# 8h: reworkStatus.regressionTarget set to target after shallow regression
# (M1 fix: phase-gate.sh reads this field for regression-aware gating)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "regression target shallow"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.regressionTarget")
assert_eq "8h: reworkStatus.regressionTarget=qa after qa regression" "qa" "$actual"
rm -rf "$TEST_ROOT"

# 8i: reworkStatus.regressionTarget set to target after deep regression with --force
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "planning" "regression target deep" "--force"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.regressionTarget")
assert_eq "8i: reworkStatus.regressionTarget=planning after planning regression --force" "planning" "$actual"
rm -rf "$TEST_ROOT"

# 8j: reworkStatus.regressionTarget=worker after worker target
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "worker" "regression target worker" "--force"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.regressionTarget")
assert_eq "8j: reworkStatus.regressionTarget=worker after worker regression --force" "worker" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 9: Logging
# ─────────────────────────────────────────────────
echo "--- Test Group 9: exec.log entry ---"

# 9a: REGRESSION line appended to exec.log
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "qa" "log test"
log_line=$(grep "REGRESSION" "$TEST_ROOT/.baton/logs/exec.log" 2>/dev/null | head -1)
log_present="false"
[ -n "$log_line" ] && log_present="true"
assert_true "9a: REGRESSION line appended to exec.log" "$log_present"

# 9b: log line contains from=review to=qa attempt=1
contains_fields="false"
if echo "$log_line" | grep -q 'from=review' && \
   echo "$log_line" | grep -q 'to=qa' && \
   echo "$log_line" | grep -q 'attempt=1'; then
  contains_fields="true"
fi
assert_true "9b: log line contains from=review to=qa attempt=1" "$contains_fields"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
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
