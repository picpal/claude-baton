#!/usr/bin/env bash
# test-rework-flow.sh — Tests for rework flow logic in agent-logger.sh
#
# Verifies:
#   1. activate_rework_if_needed: hasWarnings=false → no rework activated
#   2. activate_rework_if_needed: hasWarnings=true → rework activated, flags reset
#   3. activate_rework_if_needed: attemptCount increments on each activation
#   4. handle_review_stop: WARNING keyword in output → sets hasWarnings=true
#   5. handle_review_stop: WARN keyword in output → sets hasWarnings=true
#   6. handle_review_stop: Korean 경고 keyword → sets hasWarnings=true
#   7. handle_review_stop: rework required keyword → sets hasWarnings=true
#   8. handle_review_stop: clean output → hasWarnings stays false
#   9. handle_review_stop: all reviewers done + hasWarnings=true → rework activated
#  10. handle_review_stop: all reviewers done + hasWarnings=false → rework not activated
#  11. reviewTracker.completed reset on rework activation
#  12. reworkStatus.hasWarnings reset to false after activation

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

# Helper: write a state.json for rework tests
write_rework_state() {
  local dir="$1"
  local has_warnings="${2:-false}"
  local rework_active="${3:-false}"
  local attempt_count="${4:-0}"
  local worker_done="${5:-true}"
  local qa_unit="${6:-true}"
  local qa_int="${7:-true}"
  local review_done="${8:-false}"
  local review_completed="${9:-[]}"
  local review_expected="${10:-3}"

  python3 -c "
import json

has_warnings_val = ('$has_warnings' == 'true')
rework_val = ('$rework_active' == 'true')
worker_val = ('$worker_done' == 'true')
qa_unit_val = ('$qa_unit' == 'true')
qa_int_val = ('$qa_int' == 'true')
review_done_val = ('$review_done' == 'true')

state = {
    'version': 2,
    'currentTier': 2,
    'currentPhase': 'review',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': worker_val,
        'qaUnitPassed': qa_unit_val,
        'qaIntegrationPassed': qa_int_val,
        'reviewCompleted': review_done_val,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': int('$review_expected'), 'completed': $review_completed},
    'workerTracker': {'expected': 2, 'doneCount': 2},
    'qaRetryCount': {},
    'reworkStatus': {
        'active': rework_val,
        'attemptCount': int('$attempt_count'),
        'hasWarnings': has_warnings_val
    },
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
"
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

# Helper: simulate a SubagentStop hook event for a review agent
make_review_stop_json() {
  local agent_name="$1"
  local output_text="$2"
  python3 -c "
import json, sys
agent_name = sys.argv[1]
output_text = sys.argv[2]
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_name': agent_name,
    'tool_response': {
        'content': output_text
    }
}, ensure_ascii=False))
" "$agent_name" "$output_text"
}

# Helper: run agent-logger.sh stop event
run_agent_stop() {
  local baton_root="$1"
  local agent_name="$2"
  local output_text="${3:-}"
  local exit_code=0
  local json
  json=$(make_review_stop_json "$agent_name" "$output_text")
  echo "$json" | BATON_ROOT="$baton_root" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

echo "=== rework-flow Tests (agent-logger.sh) ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: activate_rework_if_needed behavior
# Tested via integration: all reviewers done triggers activate_rework_if_needed
# ─────────────────────────────────────────────────
echo "--- Test Group 1: activate_rework_if_needed logic (via integration) ---"

# 1a: hasWarnings=false + all reviewers done → rework NOT activated
# Set up: 2 of 3 reviewers done, hasWarnings=false; last reviewer sends clean output
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All tests pass. No issues found."
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
assert_false "1a: hasWarnings=false + all reviewers done → rework NOT activated" "$actual"
rm -rf "$TEST_ROOT"

# 1b: hasWarnings=true + all reviewers done → rework IS activated
# Set up: 2 of 3 reviewers done, hasWarnings=true (previous reviewer warned); last reviewer sends clean output
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "true" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All tests pass."
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
assert_true "1b: hasWarnings=true + all reviewers done → rework IS activated" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 2: Warning detection in review output
# ─────────────────────────────────────────────────
echo "--- Test Group 2: Warning detection from review agent output ---"

# 2a: review output contains "WARNING" → hasWarnings=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian"]' "3"
run_agent_stop "$TEST_ROOT" "Quality Inspector: code-quality" "Code review done. WARNING: missing error handling in utils.sh"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_true "2a: 'WARNING' in output → hasWarnings=true" "$actual"
rm -rf "$TEST_ROOT"

# 2b: review output contains "WARN" → hasWarnings=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian"]' "3"
run_agent_stop "$TEST_ROOT" "Quality Inspector: code-quality" "WARN: potential null dereference found"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_true "2b: 'WARN' in output → hasWarnings=true" "$actual"
rm -rf "$TEST_ROOT"

# 2c: review output contains Korean 경고 → hasWarnings=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "경고: 테스트 커버리지가 80% 미만입니다"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_true "2c: '경고' in output → hasWarnings=true" "$actual"
rm -rf "$TEST_ROOT"

# 2d: review output contains "rework required" → hasWarnings=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian"]' "3"
run_agent_stop "$TEST_ROOT" "Security Guardian: security" "Security review complete. Rework Required: fix SQL injection risk"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_true "2d: 'rework required' in output → hasWarnings=true" "$actual"
rm -rf "$TEST_ROOT"

# 2e: clean review output → hasWarnings stays false
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian"]' "3"
run_agent_stop "$TEST_ROOT" "Quality Inspector: code-quality" "All checks passed. Code quality is good."
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_false "2e: clean output → hasWarnings stays false" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 3: All reviewers complete + rework activation
# ─────────────────────────────────────────────────
echo "--- Test Group 3: All reviewers complete → rework flow ---"

# 3a: all reviewers done + hasWarnings=true → rework activated, flags reset
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
# 2 of 3 reviewers already done, hasWarnings already true
write_rework_state "$TEST_ROOT" "true" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All tests pass. Code looks good."
# After 3rd reviewer: rework should be active
actual_rework=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
actual_worker_done=$(read_state_field "$TEST_ROOT" "phaseFlags.workerCompleted")
actual_qa_unit=$(read_state_field "$TEST_ROOT" "phaseFlags.qaUnitPassed")
actual_qa_int=$(read_state_field "$TEST_ROOT" "phaseFlags.qaIntegrationPassed")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
assert_true "3a: all reviewers + hasWarnings=true → reworkStatus.active=true" "$actual_rework"
assert_false "3a: rework activated → phaseFlags.workerCompleted reset to false" "$actual_worker_done"
assert_false "3a: rework activated → phaseFlags.qaUnitPassed reset to false" "$actual_qa_unit"
assert_false "3a: rework activated → phaseFlags.qaIntegrationPassed reset to false" "$actual_qa_int"
assert_false "3a: rework activated → phaseFlags.reviewCompleted reset to false" "$actual_review"
rm -rf "$TEST_ROOT"

# 3b: all reviewers done + hasWarnings=false → no rework
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All tests pass. Code looks good."
actual_rework=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
actual_review=$(read_state_field "$TEST_ROOT" "phaseFlags.reviewCompleted")
assert_false "3b: all reviewers + hasWarnings=false → rework NOT activated" "$actual_rework"
assert_true "3b: all reviewers + no warnings → reviewCompleted=true" "$actual_review"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 4: attemptCount increments
# ─────────────────────────────────────────────────
echo "--- Test Group 4: attemptCount increments on each rework ---"

# 4a: first rework → attemptCount=1
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "true" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All checks pass."
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.attemptCount")
assert_eq "4a: first rework → attemptCount=1" "1" "$actual"
rm -rf "$TEST_ROOT"

# 4b: second rework → attemptCount=2
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "true" "false" "1" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All checks pass."
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.attemptCount")
assert_eq "4b: second rework → attemptCount=2" "2" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 5: reviewTracker.completed and hasWarnings reset
# ─────────────────────────────────────────────────
echo "--- Test Group 5: reviewTracker.completed and hasWarnings reset after rework ---"

# 5a: reviewTracker.completed reset to empty after rework activation
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "true" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All checks pass."
actual=$(read_state_field "$TEST_ROOT" "reviewTracker.completed")
assert_eq "5a: rework activated → reviewTracker.completed reset to []" "[]" "$actual"
rm -rf "$TEST_ROOT"

# 5b: hasWarnings reset to false after rework activation
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "true" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All checks pass."
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_false "5b: rework activated → hasWarnings reset to false" "$actual"
rm -rf "$TEST_ROOT"

# 5c: workerTracker.doneCount reset to 0 after rework activation
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "true" "false" "0" "true" "true" "true" "false" '["Security Guardian","Quality Inspector"]' "3"
run_agent_stop "$TEST_ROOT" "TDD Enforcer: tdd-check" "All checks pass."
actual=$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")
assert_eq "5c: rework activated → workerTracker.doneCount reset to 0" "0" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 6: 개선 필요 (Korean "improvement needed") keyword
# ─────────────────────────────────────────────────
echo "--- Test Group 6: Korean keywords trigger warning detection ---"

# 6a: 개선 필요 keyword → hasWarnings=true
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_rework_state "$TEST_ROOT" "false" "false" "0" "true" "true" "true" "false" '["Security Guardian"]' "3"
run_agent_stop "$TEST_ROOT" "Quality Inspector: code-quality" "코드 리뷰 완료. 개선 필요: 에러 핸들링 강화 필요"
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_true "6a: '개선 필요' in output → hasWarnings=true" "$actual"
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
