#!/usr/bin/env bash
# test-qa-fail-respawn.sh — Tests for F4 QA auto-regression dispatch
#
# Verifies that handle_qa_unit_stop and handle_qa_integration_stop
# automatically call regress_to_phase on FAIL/ESCALATED results:
#
#   1. QA FAIL with retry_count=0 → regress to worker, currentPhase=worker, workerCompleted=false
#   2. QA FAIL with retry_count=2 (3rd attempt, QA_MAX_RETRIES=3) → regress to taskmgr (--force)
#   3. QA FAIL with retry_count=2 + QA_MAX_RETRIES=5 → still regresses to worker (not exhausted)
#   4. QA ESCALATED → regress to taskmgr, qaRetryCount=99
#   5. QA PASS → no regress, qaUnitPassed=true (sanity)
#   6. .agent-stack handling: pop happens before QA handler, so regress_to_phase succeeds
#   7. regress_to_phase failure logged to exec.log but does not crash the hook
#   8. handle_qa_integration_stop mirrors handle_qa_unit_stop for FAIL
#   9. handle_qa_integration_stop mirrors handle_qa_unit_stop for ESCALATED

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

# Initialize state.json with currentPhase=qa and optional qaRetryCount map
init_qa_state() {
  local dir="$1"
  local qa_retry_json="${2:-{\}}"
  local tier="${3:-2}"
  python3 - "$qa_retry_json" "$tier" <<'PYEOF'
import json, sys, os

qa_retry = json.loads(sys.argv[1])
tier = int(sys.argv[2])

state = {
    'version': 3,
    'currentTier': tier,
    'currentPhase': 'qa',
    'securityHalt': False,
    'phaseFlags': {
        'issueRegistered': True,
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker':   {'expected': 3, 'completed': []},
    'workerTracker':   {'expected': 1, 'doneCount': 1},
    'qaRetryCount':    qa_retry,
    'reworkStatus':    {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [],
    'artifactStale':   {},
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

# Build SubagentStop JSON for QA unit
make_qa_unit_stop_json() {
  local marker="$1"
  python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:qa-unit',
    'agent_name': 'claude-baton:qa-unit',
    'tool_response': {'content': 'QA check complete.\n' + sys.argv[1]}
}, ensure_ascii=False))
" "$marker"
}

# Build SubagentStop JSON for QA integration
make_qa_integration_stop_json() {
  local marker="$1"
  python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:qa-integration',
    'agent_name': 'claude-baton:qa-integration',
    'tool_response': {'content': 'Integration QA complete.\n' + sys.argv[1]}
}, ensure_ascii=False))
" "$marker"
}

# Run agent-logger stop with the given JSON payload
# Optionally override QA_MAX_RETRIES via env
run_qa_stop() {
  local baton_root="$1"
  local json_data="$2"
  local max_retries="${3:-}"
  local exit_code=0

  if [ -n "$max_retries" ]; then
    echo "$json_data" \
      | BATON_ROOT="$baton_root" QA_MAX_RETRIES="$max_retries" \
        bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  else
    echo "$json_data" \
      | BATON_ROOT="$baton_root" \
        bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  fi
  return 0  # hook exit codes do not propagate test assertions
}

echo "=== F4 QA Auto-Regression Dispatch Tests ==="
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 1: QA FAIL retry_count=0 → regresses to worker
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 1: QA FAIL (1st attempt) → regress to worker ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_worker_done=$(read_state_field "$T" "phaseFlags.workerCompleted")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")
actual_rework=$(read_state_field "$T" "reworkStatus.active")

assert_eq "1a: currentPhase=worker after 1st QA FAIL" "worker" "$actual_phase"
assert_eq "1b: phaseFlags.workerCompleted=false after regress" "false" "$actual_worker_done"
assert_eq "1c: qaRetryCount.task-01=1 (incremented)" "1" "$actual_retry"
assert_true "1d: reworkStatus.active=true" "$actual_rework"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 2: QA FAIL retry_count=2 (3rd attempt, threshold=3) → regress to taskmgr
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 2: QA FAIL (3rd attempt, exhausted) → regress to taskmgr ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{"task-01": 2}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_taskmgr_done=$(read_state_field "$T" "phaseFlags.taskMgrCompleted")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")

assert_eq "2a: currentPhase=taskmgr after 3rd QA FAIL" "taskmgr" "$actual_phase"
assert_eq "2b: phaseFlags.taskMgrCompleted=false after regress" "false" "$actual_taskmgr_done"
assert_eq "2c: qaRetryCount.task-01=3 (incremented)" "3" "$actual_retry"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 3: QA FAIL retry_count=2 + QA_MAX_RETRIES=5 → still worker (not exhausted)
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 3: QA FAIL count=2, QA_MAX_RETRIES=5 → still regress to worker ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{"task-01": 2}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json" "5"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")

assert_eq "3a: currentPhase=worker (QA_MAX_RETRIES=5, count=3 < 5)" "worker" "$actual_phase"
assert_eq "3b: qaRetryCount.task-01=3 (incremented)" "3" "$actual_retry"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 4: QA ESCALATED → regress to taskmgr, qaRetryCount=99
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 4: QA ESCALATED → regress to taskmgr, qaRetryCount=99 ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:ESCALATED:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")
actual_escalated=$(read_state_field "$T" "qaEscalated.task-01")
actual_rework=$(read_state_field "$T" "reworkStatus.active")

assert_eq "4a: currentPhase=taskmgr after ESCALATED" "taskmgr" "$actual_phase"
assert_eq "4b: qaRetryCount.task-01=99" "99" "$actual_retry"
assert_true "4c: qaEscalated.task-01=true" "$actual_escalated"
assert_true "4d: reworkStatus.active=true" "$actual_rework"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 5: QA PASS → no regress, qaUnitPassed=true
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 5: QA PASS → no regress, qaUnitPassed=true ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:PASS")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_qa_passed=$(read_state_field "$T" "phaseFlags.qaUnitPassed")
actual_rework=$(read_state_field "$T" "reworkStatus.active")

# On PASS: phase should advance to review (both QA flags still pending for int)
# or remain at qa (qaIntegrationPassed still false). The key check is no regression.
assert_true "5a: phaseFlags.qaUnitPassed=true on PASS" "$actual_qa_passed"
assert_eq "5b: reworkStatus.active=false on PASS (no regression)" "false" "$actual_rework"
# Phase should NOT have gone backwards to worker or taskmgr
local_phase="$actual_phase"
if [ "$local_phase" = "worker" ] || [ "$local_phase" = "taskmgr" ]; then
  assert_eq "5c: phase did NOT regress on PASS" "qa_or_review" "$local_phase"
else
  assert_eq "5c: phase did NOT regress on PASS (qa/review/done)" "qa_or_review" "qa_or_review"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 6: .agent-stack handling — pop before handler → regress_to_phase succeeds
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 6: .agent-stack is popped before QA handler fires ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2

# Simulate: QA agent was on the stack during its run
# The stop handler pops it before calling handle_qa_unit_stop
# So we pre-populate the stack and let the stop event clear it
echo "2026-04-05T00:00:00Z|claude-baton:qa-unit" > "$T/.baton/logs/.agent-stack"

json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
# If the stack was properly cleared before regress_to_phase, regression succeeds
assert_eq "6a: regress succeeds even when stack had QA entry (popped first)" "worker" "$actual_phase"

# Stack file should be gone (single entry was popped)
if [ ! -f "$T/.baton/logs/.agent-stack" ] || [ ! -s "$T/.baton/logs/.agent-stack" ]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 6b: .agent-stack cleared after stop (no residual entries)"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 6b: .agent-stack should be empty after stop"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 7: regress_to_phase failure (securityHalt=true) does NOT crash hook
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 7: regress_to_phase failure does not crash the hook ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
# Set securityHalt to block regress_to_phase (returns exit 3)
python3 -c "
import json
with open('$T/.baton/state.json') as f:
    d = json.load(f)
d['securityHalt'] = True
with open('$T/.baton/state.json', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"

json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
hook_exit=0
echo "$json" | BATON_ROOT="$T" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || hook_exit=$?

# Hook must exit 0 even when regress_to_phase fails internally
TOTAL=$((TOTAL + 1))
if [ "$hook_exit" -eq 0 ]; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 7a: hook exits 0 even when regress_to_phase fails (securityHalt)"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 7a: hook should exit 0 but exited $hook_exit"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 8: handle_qa_integration_stop mirrors handle_qa_unit_stop for FAIL
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 8: handle_qa_integration_stop FAIL → regress to worker ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_integration_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_worker_done=$(read_state_field "$T" "phaseFlags.workerCompleted")

assert_eq "8a: Integration QA FAIL → currentPhase=worker" "worker" "$actual_phase"
assert_eq "8b: phaseFlags.workerCompleted=false after integration QA FAIL" "false" "$actual_worker_done"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 9: handle_qa_integration_stop ESCALATED → regress to taskmgr
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 9: handle_qa_integration_stop ESCALATED → regress to taskmgr ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_integration_stop_json "QA_RESULT:ESCALATED:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")

assert_eq "9a: Integration QA ESCALATED → currentPhase=taskmgr" "taskmgr" "$actual_phase"
assert_eq "9b: qaRetryCount.task-01=99 after ESCALATED" "99" "$actual_retry"
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
