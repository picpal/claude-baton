#!/usr/bin/env bash
# test-qa-retry-count.sh — Tests for qaRetryCount tracking and QA_RESULT:ESCALATED parsing
#
# Verifies (handle_qa_unit_stop and handle_qa_integration_stop):
#   1. QA PASS: qaRetryCount unchanged
#   2. QA FAIL with task-id: qaRetryCount.{task-id} incremented from 0 to 1
#   3. Repeated QA FAIL: qaRetryCount.{task-id} incremented to 2 then 3
#   4. QA ESCALATED: qaRetryCount.{task-id} set to 99
#   5. QA FAIL without task-id: qaRetryCount.global incremented
#   6. ESCALATED sets escalationMarker in state.json
#   7. handle_qa_integration_stop: FAIL increments qaRetryCount.{task-id}
#   8. handle_qa_integration_stop: ESCALATED sets qaRetryCount.{task-id}=99
#   9. QA PASS does NOT affect phaseFlags negatively (qaUnitPassed set to true)
#  10. ESCALATED with no task-id uses "global" key

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
    echo -e "${RED}FAIL${NC}: $test_name (expected=$expected, actual=$actual)"
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

# Helper: initialize a v3-schema state.json with optional qaRetryCount entries
init_state_json() {
  local dir="$1"
  local qa_retry_count
  if [ -n "${2:-}" ]; then
    qa_retry_count="$2"
  else
    qa_retry_count="{}"
  fi
  python3 -c "
import json, sys
qa_retry = json.loads(sys.argv[1])
state = {
    'version': 3,
    'currentTier': 2,
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
    'planningTracker': { 'expected': 1, 'completed': ['Planning Agent'] },
    'reviewTracker': { 'expected': 3, 'completed': [] },
    'workerTracker': { 'expected': 1, 'doneCount': 1 },
    'qaRetryCount': qa_retry,
    'reworkStatus': { 'active': False, 'attemptCount': 0, 'hasWarnings': False },
    'regressionHistory': [],
    'artifactStale': {},
    'lastCommitAttemptCount': 0,
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$dir/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
" "$qa_retry_count"
}

# Helper: create a mock QA unit stop event JSON
make_qa_unit_stop_json() {
  local result_marker="$1"
  python3 -c "
import json, sys
marker = sys.argv[1]
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:qa-unit',
    'agent_name': 'claude-baton:qa-unit',
    'tool_response': {
        'content': 'QA check complete.\n' + marker
    }
}, ensure_ascii=False))
" "$result_marker"
}

# Helper: create a mock QA integration stop event JSON
make_qa_integration_stop_json() {
  local result_marker="$1"
  python3 -c "
import json, sys
marker = sys.argv[1]
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:qa-integration',
    'agent_name': 'claude-baton:qa-integration',
    'tool_response': {
        'content': 'Integration QA check complete.\n' + marker
    }
}, ensure_ascii=False))
" "$result_marker"
}

# Helper: run agent-logger.sh stop event
run_agent_stop() {
  local baton_root="$1"
  local json_data="$2"
  local exit_code=0
  echo "$json_data" | BATON_ROOT="$baton_root" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

echo "=== qaRetryCount + QA_RESULT:ESCALATED Parsing Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: QA PASS — qaRetryCount unchanged
# ─────────────────────────────────────────────────
echo "--- Test Group 1: QA PASS — qaRetryCount unchanged ---"

# 1a: QA PASS with existing retry count: count stays unchanged
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{"task-03": 2}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:PASS")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
assert_eq "1a: QA PASS → qaRetryCount.task-03 unchanged (stays 2)" "2" "$actual"
rm -rf "$TEST_ROOT"

# 1b: QA PASS sets phaseFlags.qaUnitPassed=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:PASS")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
assert_true "1b: QA PASS → phaseFlags.qaUnitPassed=true" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 2: QA FAIL with task-id — increment qaRetryCount
# ─────────────────────────────────────────────────
echo "--- Test Group 2: QA FAIL with task-id → increment qaRetryCount ---"

# 2a: QA FAIL with task-id on fresh state → qaRetryCount.task-03 = 1
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-03")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
assert_eq "2a: QA FAIL:task-03 first → qaRetryCount.task-03=1" "1" "$actual"
rm -rf "$TEST_ROOT"

# 2b: QA FAIL increments from 1 → 2
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{"task-03": 1}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-03")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
assert_eq "2b: QA FAIL:task-03 second → qaRetryCount.task-03=2" "2" "$actual"
rm -rf "$TEST_ROOT"

# 2c: QA FAIL increments from 2 → 3
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{"task-03": 2}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-03")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
assert_eq "2c: QA FAIL:task-03 third → qaRetryCount.task-03=3" "3" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 3: QA ESCALATED — set qaRetryCount to 99
# ─────────────────────────────────────────────────
echo "--- Test Group 3: QA ESCALATED → qaRetryCount.{task-id}=99 ---"

# 3a: QA ESCALATED with task-id → qaRetryCount.task-03 = 99
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{"task-03": 3}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:ESCALATED:task-03")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
assert_eq "3a: QA ESCALATED:task-03 → qaRetryCount.task-03=99" "99" "$actual"
rm -rf "$TEST_ROOT"

# 3b: QA ESCALATED sets escalation marker in state.json
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:ESCALATED:task-03")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaEscalated.task-03")
assert_true "3b: QA ESCALATED:task-03 → qaEscalated.task-03=true" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 4: QA FAIL without task-id — use "global" key
# ─────────────────────────────────────────────────
echo "--- Test Group 4: QA FAIL without task-id → qaRetryCount.global ---"

# 4a: QA FAIL without task-id → qaRetryCount.global incremented from 0 to 1
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:FAIL")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.global")
assert_eq "4a: QA FAIL (no task-id) → qaRetryCount.global=1" "1" "$actual"
rm -rf "$TEST_ROOT"

# 4b: QA FAIL without task-id → qaRetryCount.global incremented from 1 to 2
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{"global": 1}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:FAIL")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.global")
assert_eq "4b: QA FAIL (no task-id) second → qaRetryCount.global=2" "2" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 5: QA ESCALATED without task-id — use "global" key
# ─────────────────────────────────────────────────
echo "--- Test Group 5: QA ESCALATED without task-id → global key ---"

# 5a: QA ESCALATED without task-id → qaRetryCount.global = 99
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:ESCALATED")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.global")
assert_eq "5a: QA ESCALATED (no task-id) → qaRetryCount.global=99" "99" "$actual"
rm -rf "$TEST_ROOT"

# 5b: QA ESCALATED without task-id → qaEscalated.global = true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:ESCALATED")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaEscalated.global")
assert_true "5b: QA ESCALATED (no task-id) → qaEscalated.global=true" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 6: handle_qa_integration_stop parity
# ─────────────────────────────────────────────────
echo "--- Test Group 6: handle_qa_integration_stop — same logic ---"

# 6a: Integration QA PASS → qaIntegrationPassed=true, qaRetryCount unchanged
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{"task-05": 1}'
json_data=$(make_qa_integration_stop_json "QA_RESULT:PASS")
run_agent_stop "$TEST_ROOT" "$json_data"
actual_passed=$(read_state_field "$TEST_ROOT" "phaseFlags.qaIntegrationPassed")
actual_count=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-05")
assert_true "6a: Integration QA PASS → qaIntegrationPassed=true" "$actual_passed"
assert_eq "6a: Integration QA PASS → qaRetryCount.task-05 unchanged (stays 1)" "1" "$actual_count"
rm -rf "$TEST_ROOT"

# 6b: Integration QA FAIL with task-id → qaRetryCount.task-05 incremented
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{}'
json_data=$(make_qa_integration_stop_json "QA_RESULT:FAIL:task-05")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-05")
assert_eq "6b: Integration QA FAIL:task-05 → qaRetryCount.task-05=1" "1" "$actual"
rm -rf "$TEST_ROOT"

# 6c: Integration QA ESCALATED with task-id → qaRetryCount.task-05=99
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT"
json_data=$(make_qa_integration_stop_json "QA_RESULT:ESCALATED:task-05")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-05")
assert_eq "6c: Integration QA ESCALATED:task-05 → qaRetryCount.task-05=99" "99" "$actual"
rm -rf "$TEST_ROOT"

# 6d: Integration QA ESCALATED → qaEscalated.task-05=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT"
json_data=$(make_qa_integration_stop_json "QA_RESULT:ESCALATED:task-05")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "qaEscalated.task-05")
assert_true "6d: Integration QA ESCALATED:task-05 → qaEscalated.task-05=true" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 7: Multiple task-ids are tracked independently
# ─────────────────────────────────────────────────
echo "--- Test Group 7: Multiple task-ids tracked independently ---"

# 7a: FAIL for task-03 does not affect task-05 count
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
init_state_json "$TEST_ROOT" '{"task-03": 0, "task-05": 2}'
json_data=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-03")
run_agent_stop "$TEST_ROOT" "$json_data"
actual_03=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-03")
actual_05=$(read_state_field "$TEST_ROOT" "qaRetryCount.task-05")
assert_eq "7a: FAIL:task-03 increments task-03 (0->1)" "1" "$actual_03"
assert_eq "7a: FAIL:task-03 does not change task-05 (stays 2)" "2" "$actual_05"
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
