#!/usr/bin/env bash
# test-phase-gate-regression.sh — Tests for phase-gate.sh
#
# Verifies:
#   1. detect_agent_type() in phase-gate.sh matches all 28 patterns
#      from agent-logger.sh (15 *:suffix + 13 legacy)
#   2. reworkStatus.regressionTarget="worker" allows worker spawn
#   3. reworkStatus.regressionTarget="worker" blocks qa-unit/qa-integration/review spawns
#   4. reworkStatus.regressionTarget="planning" allows planning spawn
#   5. securityHalt=true blocks ALL spawns (existing behavior preserved)
#   6. Empty regressionTarget + reworkStatus.active=false → normal flow
#   7. .agent-stack non-empty during regression → block regressing agent spawns
#   8. SECURITY rollback message mentions rollback procedure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PHASE_GATE="$SCRIPT_DIR/../phase-gate.sh"

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

# ---------------------------------------------------------------------------
# Group A: detect_agent_type() pattern parity with agent-logger.sh
# ---------------------------------------------------------------------------
# Extract detect_agent_type from phase-gate.sh and evaluate it in this shell
echo "=== Group A: detect_agent_type() parity (phase-gate.sh ↔ agent-logger.sh) ==="
echo ""

DETECT_FN=$(awk '/^detect_agent_type\(\)/{found=1} found{print} found && /^\}$/{exit}' "$PHASE_GATE")
eval "$DETECT_FN"

# --- 15 *:suffix patterns (must be present in phase-gate.sh) ---
assert_eq "A01: claude-baton:security-guardian -> review" \
  "review" "$(detect_agent_type "claude-baton:security-guardian")"
assert_eq "A02: claude-baton:quality-inspector -> review" \
  "review" "$(detect_agent_type "claude-baton:quality-inspector")"
assert_eq "A03: claude-baton:tdd-enforcer-reviewer -> review" \
  "review" "$(detect_agent_type "claude-baton:tdd-enforcer-reviewer")"
assert_eq "A04: claude-baton:performance-analyst -> review" \
  "review" "$(detect_agent_type "claude-baton:performance-analyst")"
assert_eq "A05: claude-baton:standards-keeper -> review" \
  "review" "$(detect_agent_type "claude-baton:standards-keeper")"
assert_eq "A06: claude-baton:worker-agent -> worker" \
  "worker" "$(detect_agent_type "claude-baton:worker-agent")"
assert_eq "A07: claude-baton:qa-unit -> qa-unit" \
  "qa-unit" "$(detect_agent_type "claude-baton:qa-unit")"
assert_eq "A08: claude-baton:qa-integration -> qa-integration" \
  "qa-integration" "$(detect_agent_type "claude-baton:qa-integration")"
assert_eq "A09: claude-baton:analysis-agent -> analysis" \
  "analysis" "$(detect_agent_type "claude-baton:analysis-agent")"
assert_eq "A10: claude-baton:interview-agent -> interview" \
  "interview" "$(detect_agent_type "claude-baton:interview-agent")"
assert_eq "A11: claude-baton:planning-architect -> planning" \
  "planning" "$(detect_agent_type "claude-baton:planning-architect")"
assert_eq "A12: claude-baton:planning-security -> planning" \
  "planning" "$(detect_agent_type "claude-baton:planning-security")"
assert_eq "A13: claude-baton:planning-dev-lead -> planning" \
  "planning" "$(detect_agent_type "claude-baton:planning-dev-lead")"
assert_eq "A14: claude-baton:task-manager -> taskmgr" \
  "taskmgr" "$(detect_agent_type "claude-baton:task-manager")"
assert_eq "A15: claude-baton:issue-register -> issue-register" \
  "issue-register" "$(detect_agent_type "claude-baton:issue-register")"

# --- 13 legacy patterns (must remain functional) ---
assert_eq "A16: legacy analysis:foo -> analysis" \
  "analysis" "$(detect_agent_type "analysis:some agent")"
assert_eq "A17: legacy interview:foo -> interview" \
  "interview" "$(detect_agent_type "interview:some agent")"
assert_eq "A18: legacy planning:foo -> planning" \
  "planning" "$(detect_agent_type "planning:foo")"
assert_eq "A19: legacy planning-foo -> planning" \
  "planning" "$(detect_agent_type "planning-security")"
assert_eq "A20: legacy taskmgr:foo -> taskmgr" \
  "taskmgr" "$(detect_agent_type "taskmgr:task manager")"
assert_eq "A21: legacy worker:foo -> worker" \
  "worker" "$(detect_agent_type "worker:task-01")"
assert_eq "A22: legacy qa-unit:foo -> qa-unit" \
  "qa-unit" "$(detect_agent_type "qa-unit:test suite")"
assert_eq "A23: legacy qa-integration:foo -> qa-integration" \
  "qa-integration" "$(detect_agent_type "qa-integration:e2e tests")"
assert_eq "A24: legacy security guardian:foo -> review" \
  "review" "$(detect_agent_type "security guardian:review")"
assert_eq "A25: legacy quality inspector:foo -> review" \
  "review" "$(detect_agent_type "quality inspector:review")"
assert_eq "A26: legacy tdd enforcer:foo -> review" \
  "review" "$(detect_agent_type "tdd enforcer:review")"
assert_eq "A27: legacy performance analyst:foo -> review" \
  "review" "$(detect_agent_type "performance analyst:check")"
assert_eq "A28: legacy standards keeper:foo -> review" \
  "review" "$(detect_agent_type "standards keeper:check")"

# Unknown
assert_eq "A29: unknown agent -> unknown" \
  "unknown" "$(detect_agent_type "some-random-agent")"

echo ""

# ---------------------------------------------------------------------------
# Helpers: end-to-end phase-gate.sh invocation with stubbed BATON_ROOT
# ---------------------------------------------------------------------------

# Helper: write a v3 state.json into a test root
write_state() {
  local dir="$1"
  local tier="${2:-2}"
  local phase="${3:-worker}"
  local rework_active="${4:-false}"
  local regression_target="${5:-null}"
  local security_halt="${6:-false}"
  local worker_done="${7:-false}"
  local qa_unit="${8:-false}"
  local qa_int="${9:-false}"
  local review_done="${10:-false}"

  python3 -c "
import json, os
state = {
    'version': 3,
    'currentTier': int('$tier'),
    'currentPhase': '$phase',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': ('$worker_done' == 'true'),
        'qaUnitPassed': ('$qa_unit' == 'true'),
        'qaIntegrationPassed': ('$qa_int' == 'true'),
        'reviewCompleted': ('$review_done' == 'true'),
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 1, 'completed': ['Planning Agent'] },
    'reviewTracker': { 'expected': 3, 'completed': [] },
    'workerTracker': { 'expected': 2, 'doneCount': 0 },
    'qaRetryCount': {},
    'reworkStatus': {
        'active': ('$rework_active' == 'true'),
        'attemptCount': 0,
        'hasWarnings': False,
        'regressionTarget': (None if '$regression_target' == 'null' else '$regression_target')
    },
    'regressionHistory': [],
    'artifactStale': {},
    'lastCommitAttemptCount': 0,
    'securityHalt': ('$security_halt' == 'true'),
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
os.makedirs('$dir/.baton', exist_ok=True)
with open('$dir/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
}

# Helper: build a PreToolUse hook JSON for an Agent invocation with given desc
make_hook_json() {
  local desc="$1"
  python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'PreToolUse',
    'session_id': 'test',
    'tool_name': 'Agent',
    'tool_input': {
        'description': sys.argv[1]
    }
}, ensure_ascii=False))
" "$desc"
}

# Helper: run phase-gate.sh — returns exit code
run_phase_gate() {
  local baton_root="$1"
  local desc="$2"
  local exit_code=0
  local json
  json=$(make_hook_json "$desc")
  echo "$json" | BATON_ROOT="$baton_root" bash "$PHASE_GATE" >/dev/null 2>&1 || exit_code=$?
  echo "$exit_code"
}

# Helper: run phase-gate.sh — returns combined stdout+stderr
run_phase_gate_output() {
  local baton_root="$1"
  local desc="$2"
  local json
  json=$(make_hook_json "$desc")
  echo "$json" | BATON_ROOT="$baton_root" bash "$PHASE_GATE" 2>&1 || true
}

# ---------------------------------------------------------------------------
# Group B: regressionTarget gating
# ---------------------------------------------------------------------------
echo "=== Group B: regressionTarget gating ==="
echo ""

# B01: regressionTarget=worker, spawn worker → ALLOW (exit 0)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "true" "worker" "false" "false" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "worker:task-01 implement feature")
assert_eq "B01: regressionTarget=worker allows worker spawn" "0" "$actual"
rm -rf "$TEST_ROOT"

# B02: regressionTarget=worker, spawn qa-unit → BLOCK (exit 2)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "true" "worker" "false" "false" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "qa-unit:run unit tests")
assert_eq "B02: regressionTarget=worker blocks qa-unit spawn" "2" "$actual"
rm -rf "$TEST_ROOT"

# B03: regressionTarget=worker, spawn qa-integration → BLOCK
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "true" "worker" "false" "false" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "qa-integration:run e2e tests")
assert_eq "B03: regressionTarget=worker blocks qa-integration spawn" "2" "$actual"
rm -rf "$TEST_ROOT"

# B04: regressionTarget=worker, spawn review (Security Guardian) → BLOCK
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "true" "worker" "false" "false" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "Security Guardian: review")
assert_eq "B04: regressionTarget=worker blocks review spawn" "2" "$actual"
rm -rf "$TEST_ROOT"

# B05: regressionTarget=planning, spawn planning → ALLOW
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "planning" "true" "planning" "false" "false" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "planning:re-plan after security halt")
assert_eq "B05: regressionTarget=planning allows planning spawn" "0" "$actual"
rm -rf "$TEST_ROOT"

# B06: regressionTarget=planning, spawn worker → BLOCK (worker is later than planning)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "planning" "true" "planning" "false" "false" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "worker:task-01")
assert_eq "B06: regressionTarget=planning blocks worker spawn" "2" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ---------------------------------------------------------------------------
# Group C: securityHalt overrides everything
# ---------------------------------------------------------------------------
echo "=== Group C: securityHalt blocks all spawns ==="
echo ""

# C01: securityHalt=true blocks worker
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "false" "null" "true"
actual=$(run_phase_gate "$TEST_ROOT" "worker:task-01")
assert_eq "C01: securityHalt blocks worker" "2" "$actual"
rm -rf "$TEST_ROOT"

# C02: securityHalt=true blocks analysis (even with new pipeline phase)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "done" "false" "null" "true"
actual=$(run_phase_gate "$TEST_ROOT" "analysis:start new pipeline")
assert_eq "C02: securityHalt blocks analysis" "2" "$actual"
rm -rf "$TEST_ROOT"

# C03: securityHalt error message mentions rollback procedure
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "false" "null" "true"
output=$(run_phase_gate_output "$TEST_ROOT" "worker:task-01")
if echo "$output" | grep -qiE 'rollback'; then
  assert_eq "C03: securityHalt error mentions rollback" "yes" "yes"
else
  assert_eq "C03: securityHalt error mentions rollback" "yes" "no (output: $output)"
fi
rm -rf "$TEST_ROOT"

echo ""

# ---------------------------------------------------------------------------
# Group D: normal flow (no regression, no security halt)
# ---------------------------------------------------------------------------
echo "=== Group D: normal flow (regressionTarget=null) ==="
echo ""

# D01: empty regressionTarget, worker phase complete, qa-unit allowed
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "qa" "false" "null" "false" "true" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "qa-unit:test")
assert_eq "D01: empty regressionTarget allows qa-unit when worker done" "0" "$actual"
rm -rf "$TEST_ROOT"

# D02: empty regressionTarget, worker not done, qa-unit blocked by prerequisites
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "false" "null" "false" "false" "false" "false" "false"
actual=$(run_phase_gate "$TEST_ROOT" "qa-unit:test")
assert_eq "D02: empty regressionTarget still enforces prerequisites" "2" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ---------------------------------------------------------------------------
# Group E: in-flight agent detection (.agent-stack non-empty during regression)
# ---------------------------------------------------------------------------
echo "=== Group E: in-flight agent guard during regression ==="
echo ""

# E01: regressionTarget=worker + .agent-stack non-empty + new worker spawn → BLOCK
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "true" "worker" "false" "false" "false" "false" "false"
echo "2026-04-05T00:00:00Z|worker:in-flight" > "$TEST_ROOT/.baton/logs/.agent-stack"
actual=$(run_phase_gate "$TEST_ROOT" "worker:task-02")
assert_eq "E01: regression+.agent-stack non-empty blocks regressing worker spawn" "2" "$actual"
rm -rf "$TEST_ROOT"

# E02: no regression + .agent-stack non-empty → ALLOW (normal flow doesn't care)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_state "$TEST_ROOT" "2" "worker" "false" "null" "false" "false" "false" "false" "false"
echo "2026-04-05T00:00:00Z|worker:other" > "$TEST_ROOT/.baton/logs/.agent-stack"
actual=$(run_phase_gate "$TEST_ROOT" "worker:task-02")
assert_eq "E02: no regression + .agent-stack non-empty allows worker spawn" "0" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
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
