#!/usr/bin/env bash
# test-phase-regression-scenarios.sh — Integration test suite for 10 regression scenarios
#
# Scenarios:
#   R1 : Review warning → rework (activate_rework_if_needed end-to-end)
#   R2 : QA failure → worker retry (regress_to_phase("worker") from qa state)
#   R3 : Post-QA additional work (regress_to_phase("worker") from review state)
#   R4 : Security Rollback (security-halt → clear → regress_to_phase("planning", --force))
#   R5 : User-initiated regression (various target phases)
#   R6 : Post-done hotfix (done state guard — exit 6; only analysis allowed)
#   R7 : Post-QA worker re-spawn (the reported bug — currentPhase must become "worker")
#   R8 : Planning conflict → re-analysis Tier 3 (regress_to_phase("analysis", --force))
#   R9 : TaskMgr re-split (regress_to_phase("taskmgr"))
#   R10: QA 3-failure escalation (qaRetryCount + ESCALATED + taskmgr regression)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_LOGGER="$SCRIPT_DIR/../agent-logger.sh"
REGRESS_SCRIPT="$SCRIPT_DIR/../regress-to-phase.sh"
SECURITY_HALT_SCRIPT="$SCRIPT_DIR/../security-halt.sh"
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

# Helper: read a field from state.json using dot notation
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

# Helper: read a nested key from artifactStale (keys contain dots, looked up directly)
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

# Helper: write a full Tier-2-at-review state.json (all phases completed)
# tier default=2, current_phase default=review, security_halt default=false
write_full_state() {
  local dir="$1"
  local tier="${2:-2}"
  local current_phase="${3:-review}"
  local security_halt="${4:-false}"
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
    'workerTracker': {'expected': 3, 'doneCount': 3},
    'qaRetryCount': {},
    'qaEscalated': {},
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

# Helper: write state for QA phase (worker done, QA not yet passed)
write_qa_phase_state() {
  local dir="$1"
  local tier="${2:-2}"
  python3 - <<PYEOF
import json
state = {
    'version': 3,
    'currentTier': $tier,
    'currentPhase': 'qa',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': []},
    'workerTracker': {'expected': 2, 'doneCount': 2},
    'qaRetryCount': {},
    'qaEscalated': {},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [],
    'artifactStale': {},
    'lastCommitAttemptCount': 0,
    'securityHalt': False,
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

# Helper: invoke regress_to_phase via sourcing the script
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

# Helper: build a SubagentStop JSON payload
make_stop_json() {
  local agent_name="$1"
  local output_text="$2"
  python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_name': sys.argv[1],
    'tool_response': {'content': sys.argv[2]}
}, ensure_ascii=False))
" "$agent_name" "$output_text"
}

# Helper: run agent-logger stop event
run_agent_stop() {
  local baton_root="$1"
  local agent_name="$2"
  local output_text="${3:-}"
  local exit_code=0
  local json
  json=$(make_stop_json "$agent_name" "$output_text")
  echo "$json" | BATON_ROOT="$baton_root" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

echo "=== Phase Regression Scenarios — Integration Tests ==="
echo ""

# ==========================================================================
# R1: Review warning → rework (activate_rework_if_needed end-to-end)
#
# Scenario: All 3 reviewers complete, one had a WARNING. After the final
# reviewer's stop event, reworkStatus.active becomes true and pipeline
# automatically resets to worker phase.
# ==========================================================================
echo "--- R1: Review warning → rework (activate_rework_if_needed) ---"

# R1a: Setup: 2 reviewers done, hasWarnings=true (already set). Third reviewer completes
# with clean output → triggers activate_rework_if_needed → regresses to worker.
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 - <<PYEOF
import json
state = {
    'version': 3, 'currentTier': 2, 'currentPhase': 'review',
    'phaseFlags': {
        'analysisCompleted': True, 'interviewCompleted': True,
        'planningCompleted': True, 'taskMgrCompleted': True,
        'workerCompleted': True, 'qaUnitPassed': True,
        'qaIntegrationPassed': True, 'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': ['Security Guardian', 'Quality Inspector']},
    'workerTracker': {'expected': 2, 'doneCount': 2},
    'qaRetryCount': {}, 'qaEscalated': {},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': True},
    'regressionHistory': [], 'artifactStale': {}, 'lastCommitAttemptCount': 0,
    'securityHalt': False, 'lastSafeTag': None,
    'issueNumber': 42, 'issueUrl': None, 'issueLabels': [], 'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2); f.write('\n')
PYEOF
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All tests pass."
# After final reviewer with hasWarnings=true: rework activates, phase → worker
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
actual_rework=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_qa_int=$(read_state_field "$TEST_ROOT" "phaseFlags.qaIntegrationPassed")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
actual_attempt=$(read_state_field "$TEST_ROOT" "reworkStatus.attemptCount")
assert_eq "R1a: rework triggered → currentPhase=worker" "worker" "$actual_phase"
assert_true "R1a: rework triggered → reworkStatus.active=true" "$actual_rework"
assert_false "R1a: rework → workerCompleted reset to false" "$actual_worker"
assert_false "R1a: rework → qaUnitPassed reset to false" "$actual_qa_unit"
assert_false "R1a: rework → qaIntegrationPassed reset to false" "$actual_qa_int"
assert_false "R1a: rework → reviewCompleted reset to false" "$actual_review"
assert_eq "R1a: rework → attemptCount=1" "1" "$actual_attempt"
rm -rf "$TEST_ROOT"

# R1b: No warning in reviewer output → rework NOT triggered, reviewCompleted=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 - <<PYEOF
import json
state = {
    'version': 3, 'currentTier': 2, 'currentPhase': 'review',
    'phaseFlags': {
        'analysisCompleted': True, 'interviewCompleted': True,
        'planningCompleted': True, 'taskMgrCompleted': True,
        'workerCompleted': True, 'qaUnitPassed': True,
        'qaIntegrationPassed': True, 'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': ['Security Guardian', 'Quality Inspector']},
    'workerTracker': {'expected': 2, 'doneCount': 2},
    'qaRetryCount': {}, 'qaEscalated': {},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [], 'artifactStale': {}, 'lastCommitAttemptCount': 0,
    'securityHalt': False, 'lastSafeTag': None,
    'issueNumber': 42, 'issueUrl': None, 'issueLabels': [], 'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2); f.write('\n')
PYEOF
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All tests pass. Code quality excellent."
actual_rework=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_false "R1b: no warnings → reworkStatus.active=false" "$actual_rework"
assert_true "R1b: no warnings → reviewCompleted=true" "$actual_review"
assert_eq "R1b: no warnings → currentPhase=done" "done" "$actual_phase"
rm -rf "$TEST_ROOT"

# R1c: Warning detected mid-review → hasWarnings becomes true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 - <<PYEOF
import json
state = {
    'version': 3, 'currentTier': 2, 'currentPhase': 'review',
    'phaseFlags': {
        'analysisCompleted': True, 'interviewCompleted': True,
        'planningCompleted': True, 'taskMgrCompleted': True,
        'workerCompleted': True, 'qaUnitPassed': True,
        'qaIntegrationPassed': True, 'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': ['Security Guardian']},
    'workerTracker': {'expected': 2, 'doneCount': 2},
    'qaRetryCount': {}, 'qaEscalated': {},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [], 'artifactStale': {}, 'lastCommitAttemptCount': 0,
    'securityHalt': False, 'lastSafeTag': None,
    'issueNumber': 42, 'issueUrl': None, 'issueLabels': [], 'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2); f.write('\n')
PYEOF
run_agent_stop "$TEST_ROOT" "Quality Inspector: code-quality" "WARNING: missing error handling"
actual_has_warnings=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_true "R1c: reviewer WARNING keyword → hasWarnings=true" "$actual_has_warnings"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R2: QA failure → worker retry
#
# Scenario: QA agent outputs QA_RESULT:FAIL. Then Main calls
# regress_to_phase("worker") from qa state (depth=1, no --force needed).
# State verification: currentPhase=worker, workerCompleted=false,
# qaRetryCount incremented.
# ==========================================================================
echo "--- R2: QA failure → worker retry ---"

# R2a: QA FAIL increments qaRetryCount, phase remains qa (flag not set)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
python3 - <<PYEOF
import json, sys
sys.argv = ['', '$TEST_ROOT']
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
d['currentPhase'] = 'qa'
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(d, f, indent=2); f.write('\n')
PYEOF
# Simulate qa-unit agent stop with QA_RESULT:FAIL:task-02
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "Running tests... QA_RESULT:FAIL:task-02"
actual_retry=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-02")
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
assert_eq "R2a: QA_RESULT:FAIL → qaRetryCount.task-02=1" "1" "$actual_retry"
assert_false "R2a: QA_RESULT:FAIL → qaUnitPassed stays false" "$actual_qa_unit"
rm -rf "$TEST_ROOT"

# R2b: After QA failure, regress_to_phase("worker") from qa state (depth=1, no --force)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'QA failed — retry worker'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R2b: regress qa→worker (depth=1) → exit 0" "0" "$exit_code"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_tracker=$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")
actual_review_completed=$(read_state_field "$TEST_ROOT" "reviewTracker.completed")
assert_eq "R2b: regress qa→worker → currentPhase=worker" "worker" "$actual_phase"
assert_false "R2b: regress qa→worker → workerCompleted=false" "$actual_worker"
assert_eq "R2b: regress qa→worker → workerTracker.doneCount=0" "0" "$actual_tracker"
assert_eq "R2b: regress qa→worker → reviewTracker.completed=[]" "[]" "$actual_review_completed"
rm -rf "$TEST_ROOT"

# R2c: QA fail statusline check — after regress qa→worker, statusline is "worker"
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_regress "$TEST_ROOT" "worker" "QA FAIL retry"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "R2c: statusline reflects worker phase after QA fail regression" "worker" "$actual_phase"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R3: Post-QA additional work (regress worker from review state)
#
# Scenario: Pipeline reached review phase. Main decides more work is needed
# (not triggered by review warnings — direct user/Main call).
# regress_to_phase("worker") from review state requires --force (depth=2).
# ==========================================================================
echo "--- R3: Post-QA additional work (review → worker, --force) ---"

# R3a: regress review→worker without --force → exit 5 (SC-REGRESS-04)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'additional work needed'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R3a: review→worker without --force → exit 5" "5" "$exit_code"
rm -rf "$TEST_ROOT"

# R3b: regress review→worker with --force → exit 0, phase=worker
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'additional work needed' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R3b: review→worker with --force → exit 0" "0" "$exit_code"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
actual_taskmgr=$(read_state_field "$TEST_ROOT" "phaseFlags.taskMgrCompleted")
assert_eq "R3b: review→worker (--force) → currentPhase=worker" "worker" "$actual_phase"
assert_false "R3b: review→worker (--force) → workerCompleted=false" "$actual_worker"
assert_false "R3b: review→worker (--force) → qaUnitPassed=false" "$actual_qa_unit"
assert_false "R3b: review→worker (--force) → reviewCompleted=false" "$actual_review"
assert_true "R3b: review→worker (--force) → taskMgrCompleted preserved=true" "$actual_taskmgr"
rm -rf "$TEST_ROOT"

# R3c: regressionHistory records the regression event
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "worker" "post-QA rework" "--force"
actual_history=$(read_state_field "$TEST_ROOT" "regressionHistory")
history_len=$(python3 -c "import json,sys; h=json.loads(sys.argv[1]); print(len(h))" "$actual_history")
assert_eq "R3c: regressionHistory has 1 entry after regression" "1" "$history_len"
history_to=$(python3 -c "import json,sys; h=json.loads(sys.argv[1]); print(h[0]['toPhase'])" "$actual_history")
assert_eq "R3c: regressionHistory[0].toPhase=worker" "worker" "$history_to"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R4: Security Rollback
#
# Scenario: security-halt.sh fires → securityHalt=true → regress_to_phase
# is blocked (exit 3). After clearing securityHalt, regress_to_phase
# ("planning", --force) succeeds from review state.
# ==========================================================================
echo "--- R4: Security Rollback sequence ---"

# R4a: security-halt.sh sets securityHalt=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
BATON_ROOT="$TEST_ROOT" bash "$SECURITY_HALT_SCRIPT" "CRITICAL" "SQL injection in api.sh" "Security Guardian" > /dev/null 2>&1 || true
actual_halt=$(read_state_field "$TEST_ROOT" "securityHalt")
assert_true "R4a: security-halt.sh → securityHalt=true" "$actual_halt"
rm -rf "$TEST_ROOT"

# R4b: With securityHalt=true, regress_to_phase is blocked (exit 3)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review" "true"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'security rollback' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R4b: securityHalt=true → regress_to_phase exit 3 (SC-REGRESS-03)" "3" "$exit_code"
rm -rf "$TEST_ROOT"

# R4c: After clearing securityHalt, regress_to_phase("planning", --force) succeeds
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
# Run security-halt then clear it
BATON_ROOT="$TEST_ROOT" bash "$SECURITY_HALT_SCRIPT" "CRITICAL" "SQL injection" "Guardian" > /dev/null 2>&1 || true
# Clear securityHalt via state_write (simulating recovery)
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_write 'securityHalt' 'false'
" > /dev/null 2>&1 || true
# Now regress_to_phase should work
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'Security rollback complete' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R4c: securityHalt cleared → regress_to_phase exit 0" "0" "$exit_code"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "R4c: after security rollback → currentPhase=planning" "planning" "$actual_phase"
rm -rf "$TEST_ROOT"

# R4d: Security rollback resets planning/taskmgr/worker/qa/review flags
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_write 'securityHalt' 'false'
" > /dev/null 2>&1 || true
run_regress "$TEST_ROOT" "planning" "Security rollback" "--force"
actual_planning=$(read_state_field "$TEST_ROOT" "phaseFlags.planningCompleted")
actual_taskmgr=$(read_state_field "$TEST_ROOT" "phaseFlags.taskMgrCompleted")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_qa=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_interview=$(read_state_field "$TEST_ROOT" "phaseFlags.interviewCompleted")
assert_false "R4d: planning regression → planningCompleted=false" "$actual_planning"
assert_false "R4d: planning regression → taskMgrCompleted=false" "$actual_taskmgr"
assert_false "R4d: planning regression → workerCompleted=false" "$actual_worker"
assert_false "R4d: planning regression → qaUnitPassed=false" "$actual_qa"
assert_true "R4d: planning regression → interviewCompleted preserved=true" "$actual_interview"
rm -rf "$TEST_ROOT"

# R4e: artifactStale after planning regression marks plan.md and todo.md
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "planning" "Security rollback" "--force"
actual_plan=$(read_artifact_stale "$TEST_ROOT" "plan.md")
actual_todo=$(read_artifact_stale "$TEST_ROOT" "todo.md")
assert_true "R4e: planning regression → artifactStale[plan.md]=true" "$actual_plan"
assert_true "R4e: planning regression → artifactStale[todo.md]=true" "$actual_todo"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R5: User-initiated regression (various target phases)
#
# Scenario: Main/User directly calls regress_to_phase to various targets.
# Verify each target's phase boundary and guard behavior.
# ==========================================================================
echo "--- R5: User-initiated regression (various targets) ---"

# R5a: review→qa (depth=1, no --force needed) → exit 0, currentPhase=qa
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'qa' 'user requested QA rerun'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R5a: review→qa (depth=1) → exit 0" "0" "$exit_code"
assert_eq "R5a: review→qa → currentPhase=qa" "qa" "$(read_state_field "$TEST_ROOT" "currentPhase")"
rm -rf "$TEST_ROOT"

# R5b: review→taskmgr (depth=3, --force required) → exit 0 with --force
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'taskmgr' 'user requested taskmgr re-split' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R5b: review→taskmgr (--force) → exit 0" "0" "$exit_code"
assert_eq "R5b: review→taskmgr → currentPhase=taskmgr" "taskmgr" "$(read_state_field "$TEST_ROOT" "currentPhase")"
rm -rf "$TEST_ROOT"

# R5c: review→interview (depth=5, --force required) → succeeds
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'interview' 'user re-interview' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R5c: review→interview (--force) → exit 0" "0" "$exit_code"
assert_eq "R5c: review→interview → currentPhase=interview" "interview" "$(read_state_field "$TEST_ROOT" "currentPhase")"
rm -rf "$TEST_ROOT"

# R5d: review→nonexistent (invalid target) → exit 1
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'deploy' 'user tried invalid phase'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R5d: invalid target 'deploy' → exit 1" "1" "$exit_code"
rm -rf "$TEST_ROOT"

# R5e: subagent active → exit 4 (SC-REGRESS-01)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
echo "2026-04-05T00:00:00Z|claude-baton:worker-agent" > "$TEST_ROOT/.baton/logs/.agent-stack"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'user tried while agents active' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R5e: .agent-stack non-empty → exit 4 (SC-REGRESS-01)" "4" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R6: Post-done hotfix
#
# Scenario: Pipeline is in "done" state. For phases other than "analysis",
# regress_to_phase must refuse with exit 6. Only analysis target is allowed
# (to start a new pipeline). The new pipeline path works.
# ==========================================================================
echo "--- R6: Post-done hotfix guard ---"

# R6a: done + target=worker → exit 6
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "done"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'worker' 'hotfix' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R6a: done + target=worker → exit 6" "6" "$exit_code"
rm -rf "$TEST_ROOT"

# R6b: done + target=qa → exit 6
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "done"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'qa' 'hotfix QA' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R6b: done + target=qa → exit 6" "6" "$exit_code"
rm -rf "$TEST_ROOT"

# R6c: done + target=planning → exit 6
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "done"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'hotfix plan' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R6c: done + target=planning → exit 6" "6" "$exit_code"
rm -rf "$TEST_ROOT"

# R6d: done + target=analysis (--force) → exit 0 (new pipeline path allowed)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "done"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'analysis' 'new pipeline for hotfix' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R6d: done + target=analysis (--force) → exit 0" "0" "$exit_code"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "R6d: done→analysis → currentPhase=analysis" "analysis" "$actual_phase"
rm -rf "$TEST_ROOT"

# R6e: done→analysis resets currentTier to null and marks complexity-score stale
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "done"
run_regress "$TEST_ROOT" "analysis" "hotfix new pipeline" "--force"
actual_tier=$(read_state_field "$TEST_ROOT" "currentTier")
actual_complexity=$(read_artifact_stale "$TEST_ROOT" "complexity-score.md")
assert_eq "R6e: done→analysis → currentTier reset to null" "null" "$actual_tier"
assert_true "R6e: done→analysis → artifactStale[complexity-score.md]=true" "$actual_complexity"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R7: Post-QA worker re-spawn (the reported bug)
#
# Scenario: The bug was that after QA failure, regress_to_phase("worker")
# should reliably set currentPhase="worker". Verify this works from qa state
# (depth=1) and from review state (depth=2, --force).
# ==========================================================================
echo "--- R7: Post-QA worker re-spawn (reported bug regression) ---"

# R7a: From qa state, regress_to_phase("worker") → currentPhase="worker"
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_regress "$TEST_ROOT" "worker" "QA FAIL re-spawn"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "R7a: qa→worker (depth=1) → currentPhase=worker" "worker" "$actual_phase"
rm -rf "$TEST_ROOT"

# R7b: workerTracker.expected and doneCount are both reset to 0 after regression
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_regress "$TEST_ROOT" "worker" "worker re-spawn"
actual_done=$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")
actual_expected=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
assert_eq "R7b: workerTracker.doneCount reset to 0" "0" "$actual_done"
assert_eq "R7b: workerTracker.expected reset to 0" "0" "$actual_expected"
rm -rf "$TEST_ROOT"

# R7c: reworkStatus.active=true after worker regression (workers can re-spawn)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_regress "$TEST_ROOT" "worker" "worker re-spawn from QA"
actual_rework=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
assert_true "R7c: after worker regression → reworkStatus.active=true" "$actual_rework"
rm -rf "$TEST_ROOT"

# R7d: QA flags (qaUnitPassed, qaIntegrationPassed) are reset after worker regression
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
# Temporarily mark qa as passed in state to simulate a scenario where qa ran briefly
python3 - <<PYEOF
import json
with open('$TEST_ROOT/.baton/state.json') as f:
    d = json.load(f)
d['phaseFlags']['qaUnitPassed'] = True
d['phaseFlags']['qaIntegrationPassed'] = True
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(d, f, indent=2); f.write('\n')
PYEOF
run_regress "$TEST_ROOT" "worker" "worker re-spawn with QA reset" "--force"
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_qa_int=$(read_state_field "$TEST_ROOT" "phaseFlags.qaIntegrationPassed")
assert_false "R7d: worker regression → qaUnitPassed reset to false" "$actual_qa_unit"
assert_false "R7d: worker regression → qaIntegrationPassed reset to false" "$actual_qa_int"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R8: Planning conflict → re-analysis (Tier 3)
#
# Scenario: Tier 3 pipeline at review. Planners conflict requiring re-analysis.
# regress_to_phase("analysis", --force) from review — resets everything,
# currentTier→null, complexity-score/plan/todo marked stale.
# ==========================================================================
echo "--- R8: Planning conflict → re-analysis (Tier 3) ---"

# R8a: Tier 3 review → analysis (--force) → exit 0
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 3 "review"
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'analysis' 'Tier 3 planning conflict' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R8a: Tier 3 review→analysis (--force) → exit 0" "0" "$exit_code"
rm -rf "$TEST_ROOT"

# R8b: After analysis regression — currentPhase=analysis, currentTier=null
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 3 "review"
run_regress "$TEST_ROOT" "analysis" "Tier 3 planning conflict" "--force"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
actual_tier=$(read_state_field "$TEST_ROOT" "currentTier")
assert_eq "R8b: Tier 3 → analysis regression → currentPhase=analysis" "analysis" "$actual_phase"
assert_eq "R8b: Tier 3 → analysis regression → currentTier=null" "null" "$actual_tier"
rm -rf "$TEST_ROOT"

# R8c: All downstream flags reset including Tier 3 planning/review flags
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 3 "review"
run_regress "$TEST_ROOT" "analysis" "Tier 3 conflict" "--force"
actual_analysis=$(read_state_field "$TEST_ROOT" "phaseFlags.analysisCompleted")
actual_interview=$(read_state_field "$TEST_ROOT" "phaseFlags.interviewCompleted")
actual_planning=$(read_state_field "$TEST_ROOT" "phaseFlags.planningCompleted")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_issue=$(read_state_field "$TEST_ROOT" "phaseFlags.issueRegistered")
assert_false "R8c: analysis regression → analysisCompleted=false" "$actual_analysis"
assert_false "R8c: analysis regression → interviewCompleted=false" "$actual_interview"
assert_false "R8c: analysis regression → planningCompleted=false" "$actual_planning"
assert_false "R8c: analysis regression → workerCompleted=false" "$actual_worker"
assert_true "R8c: analysis regression → issueRegistered preserved=true" "$actual_issue"
rm -rf "$TEST_ROOT"

# R8d: All 3 artifacts marked stale after analysis regression
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 3 "review"
run_regress "$TEST_ROOT" "analysis" "Tier 3 conflict" "--force"
actual_complexity=$(read_artifact_stale "$TEST_ROOT" "complexity-score.md")
actual_plan=$(read_artifact_stale "$TEST_ROOT" "plan.md")
actual_todo=$(read_artifact_stale "$TEST_ROOT" "todo.md")
assert_true "R8d: analysis regression → artifactStale[complexity-score.md]=true" "$actual_complexity"
assert_true "R8d: analysis regression → artifactStale[plan.md]=true" "$actual_plan"
assert_true "R8d: analysis regression → artifactStale[todo.md]=true" "$actual_todo"
rm -rf "$TEST_ROOT"

# R8e: planningTracker.completed reset after analysis regression
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 3 "review"
run_regress "$TEST_ROOT" "analysis" "Tier 3 conflict" "--force"
actual_planning_completed=$(read_state_field "$TEST_ROOT" "planningTracker.completed")
assert_eq "R8e: analysis regression → planningTracker.completed=[]" "[]" "$actual_planning_completed"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R9: TaskMgr re-split
#
# Scenario: After planning, Main decides the TaskMgr split was wrong.
# regress_to_phase("taskmgr") from worker state (depth=1, no --force).
# From review state (depth=3, --force).
# ==========================================================================
echo "--- R9: TaskMgr re-split ---"

# R9a: worker→taskmgr (depth=1, no --force) → exit 0
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
# State: pipeline at worker phase, taskMgr done but worker not started
python3 - <<PYEOF
import json
state = {
    'version': 3, 'currentTier': 2, 'currentPhase': 'worker',
    'phaseFlags': {
        'analysisCompleted': True, 'interviewCompleted': True,
        'planningCompleted': True, 'taskMgrCompleted': True,
        'workerCompleted': False, 'qaUnitPassed': False,
        'qaIntegrationPassed': False, 'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': []},
    'workerTracker': {'expected': 3, 'doneCount': 0},
    'qaRetryCount': {}, 'qaEscalated': {},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [], 'artifactStale': {}, 'lastCommitAttemptCount': 0,
    'securityHalt': False, 'lastSafeTag': None,
    'issueNumber': 42, 'issueUrl': None, 'issueLabels': [], 'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2); f.write('\n')
PYEOF
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'taskmgr' 'TaskMgr re-split needed'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R9a: worker→taskmgr (depth=1) → exit 0" "0" "$exit_code"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "R9a: worker→taskmgr → currentPhase=taskmgr" "taskmgr" "$actual_phase"
rm -rf "$TEST_ROOT"

# R9b: taskmgr regression resets workerTracker and clears review tracker
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "review"
run_regress "$TEST_ROOT" "taskmgr" "TaskMgr re-split" "--force"
actual_taskmgr=$(read_state_field "$TEST_ROOT" "phaseFlags.taskMgrCompleted")
actual_worker=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_done_count=$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")
actual_expected=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
actual_review_completed=$(read_state_field "$TEST_ROOT" "reviewTracker.completed")
assert_false "R9b: taskmgr regression → taskMgrCompleted=false" "$actual_taskmgr"
assert_false "R9b: taskmgr regression → workerCompleted=false" "$actual_worker"
assert_eq "R9b: taskmgr regression → workerTracker.doneCount=0" "0" "$actual_done_count"
assert_eq "R9b: taskmgr regression → workerTracker.expected=0" "0" "$actual_expected"
assert_eq "R9b: taskmgr regression → reviewTracker.completed=[]" "[]" "$actual_review_completed"
rm -rf "$TEST_ROOT"

# R9c: taskmgr regression marks todo.md as stale
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "worker"
run_regress "$TEST_ROOT" "taskmgr" "TaskMgr re-split from worker"
actual_todo=$(read_artifact_stale "$TEST_ROOT" "todo.md")
assert_true "R9c: taskmgr regression → artifactStale[todo.md]=true" "$actual_todo"
rm -rf "$TEST_ROOT"

# R9d: taskmgr regression preserves planningCompleted (planning not re-done)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_full_state "$TEST_ROOT" 2 "worker"
run_regress "$TEST_ROOT" "taskmgr" "TaskMgr re-split from worker"
actual_planning=$(read_state_field "$TEST_ROOT" "phaseFlags.planningCompleted")
assert_true "R9d: taskmgr regression → planningCompleted preserved=true" "$actual_planning"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# R10: QA 3-failure escalation
#
# Scenario: QA agent outputs QA_RESULT:FAIL:task-03 three consecutive times.
# On the 3rd failure, qaRetryCount.task-03 = 3.
# Then QA agent sends QA_RESULT:ESCALATED:task-03 → qaRetryCount set to 99.
# Main then calls regress_to_phase("taskmgr") to re-split the failed task.
# ==========================================================================
echo "--- R10: QA 3-failure escalation ---"

# R10a: Three consecutive QA FAIL events increment qaRetryCount to 3
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
# First FAIL
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "Test run 1. QA_RESULT:FAIL:task-03"
# Second FAIL
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "Test run 2. QA_RESULT:FAIL:task-03"
# Third FAIL
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "Test run 3. QA_RESULT:FAIL:task-03"
actual_retry=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
assert_eq "R10a: 3x QA FAIL → qaRetryCount.task-03=3" "3" "$actual_retry"
rm -rf "$TEST_ROOT"

# R10b: QA_RESULT:ESCALATED sets qaRetryCount.{task-id}=99
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "Task has failed too many times. QA_RESULT:ESCALATED:task-03"
actual_retry=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
assert_eq "R10b: QA_RESULT:ESCALATED → qaRetryCount.task-03=99" "99" "$actual_retry"
rm -rf "$TEST_ROOT"

# R10c: QA_RESULT:ESCALATED sets qaEscalated.{task-id}=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "Escalating. QA_RESULT:ESCALATED:task-03"
actual_escalated=$(read_state_field "$TEST_ROOT" "qaEscalated.task-03")
assert_true "R10c: QA_RESULT:ESCALATED → qaEscalated.task-03=true" "$actual_escalated"
rm -rf "$TEST_ROOT"

# R10d: After ESCALATED, Main calls regress_to_phase("taskmgr") to re-split
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
# Simulate ESCALATED state
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "QA_RESULT:ESCALATED:task-03"
# Main now regresses to taskmgr (from qa state, depth=2, --force needed)
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'taskmgr' 'QA escalation — re-split task-03' --force
" > /dev/null 2>&1 || exit_code=$?
assert_eq "R10d: ESCALATED → regress taskmgr (--force) → exit 0" "0" "$exit_code"
actual_phase=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "R10d: ESCALATED → regress taskmgr → currentPhase=taskmgr" "taskmgr" "$actual_phase"
rm -rf "$TEST_ROOT"

# R10e: ESCALATED with no task-id uses "global" key
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_agent_stop "$TEST_ROOT" "claude-baton:qa-unit" "Global escalation. QA_RESULT:ESCALATED"
actual_retry=$(read_state_field "$TEST_ROOT" "qaRetryCount.global")
actual_escalated=$(read_state_field "$TEST_ROOT" "qaEscalated.global")
assert_eq "R10e: ESCALATED no task-id → qaRetryCount.global=99" "99" "$actual_retry"
assert_true "R10e: ESCALATED no task-id → qaEscalated.global=true" "$actual_escalated"
rm -rf "$TEST_ROOT"

# R10f: QA integration stop ESCALATED also sets qaEscalated flag
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_qa_phase_state "$TEST_ROOT" 2
run_agent_stop "$TEST_ROOT" "claude-baton:qa-integration" "Integration escalation. QA_RESULT:ESCALATED:task-04"
actual_retry=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-04")
actual_escalated=$(read_state_field "$TEST_ROOT" "qaEscalated.task-04")
assert_eq "R10f: qa-integration ESCALATED → qaRetryCount.task-04=99" "99" "$actual_retry"
assert_true "R10f: qa-integration ESCALATED → qaEscalated.task-04=true" "$actual_escalated"
rm -rf "$TEST_ROOT"

echo ""

# ==========================================================================
# Summary
# ==========================================================================
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
