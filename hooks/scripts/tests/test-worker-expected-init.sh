#!/usr/bin/env bash
# test-worker-expected-init.sh — Tests for workerTracker.expected initialization
# in handle_analysis_stop() of agent-logger.sh
#
# Verifies:
#   1. Tier 1: workerTracker.expected is set to 1 (direct worker, no taskmgr)
#   2. Tier 2: workerTracker.expected is set to 1 as default fallback
#   3. Tier 3: workerTracker.expected is set to 1 as default fallback
#   4. Tier 2: taskmgr can overwrite workerTracker.expected with actual count

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

# Helper: create a mock analysis stop event JSON with a TIER marker
make_analysis_stop_json() {
  local tier="$1"
  python3 -c "
import json, sys
tier = sys.argv[1]
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:analysis-agent',
    'agent_name': 'claude-baton:analysis-agent',
    'tool_response': {
        'content': 'Analysis complete. TIER:' + tier
    }
}, ensure_ascii=False))
" "$tier"
}

# Helper: create a mock taskmgr stop event JSON with a WORKER_COUNT marker
make_taskmgr_stop_json() {
  local count="$1"
  python3 -c "
import json, sys
count = sys.argv[1]
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:task-manager',
    'agent_name': 'claude-baton:task-manager',
    'tool_response': {
        'content': 'Tasks created. WORKER_COUNT:' + count
    }
}, ensure_ascii=False))
" "$count"
}

# Helper: run agent-logger.sh stop event
run_agent_stop() {
  local baton_root="$1"
  local json_data="$2"
  local exit_code=0
  echo "$json_data" | BATON_ROOT="$baton_root" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

echo "=== workerTracker.expected Initialization Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: Tier 1 sets workerTracker.expected=1
# ─────────────────────────────────────────────────
echo "--- Test Group 1: Tier 1 workerTracker.expected initialization ---"

# 1a: Tier 1 analysis stop should set workerTracker.expected to 1
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
# Initialize a minimal state.json
python3 -c "
import json
state = {
    'version': 2,
    'currentTier': None,
    'currentPhase': 'analysis',
    'phaseFlags': {
        'analysisCompleted': False,
        'interviewCompleted': False,
        'planningCompleted': False,
        'taskMgrCompleted': False,
        'workerCompleted': False,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
        'issueRegistered': False
    },
    'planningTracker': { 'expected': 0, 'completed': [] },
    'reviewTracker': { 'expected': 0, 'completed': [] },
    'workerTracker': { 'expected': 0, 'doneCount': 0 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0 },
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
json_data=$(make_analysis_stop_json "1")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
assert_eq "1a: Tier 1 analysis stop -> workerTracker.expected=1" "1" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 2: Tier 2 sets workerTracker.expected=1 (default fallback)
# ─────────────────────────────────────────────────
echo "--- Test Group 2: Tier 2 workerTracker.expected initialization ---"

# 2a: Tier 2 analysis stop should set workerTracker.expected to 1 as default
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 -c "
import json
state = {
    'version': 2,
    'currentTier': None,
    'currentPhase': 'analysis',
    'phaseFlags': {
        'analysisCompleted': False,
        'interviewCompleted': False,
        'planningCompleted': False,
        'taskMgrCompleted': False,
        'workerCompleted': False,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 0, 'completed': [] },
    'reviewTracker': { 'expected': 0, 'completed': [] },
    'workerTracker': { 'expected': 0, 'doneCount': 0 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0 },
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
json_data=$(make_analysis_stop_json "2")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
assert_eq "2a: Tier 2 analysis stop -> workerTracker.expected=1 (default)" "1" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 3: Tier 3 sets workerTracker.expected=1 (default fallback)
# ─────────────────────────────────────────────────
echo "--- Test Group 3: Tier 3 workerTracker.expected initialization ---"

# 3a: Tier 3 analysis stop should set workerTracker.expected to 1 as default
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 -c "
import json
state = {
    'version': 2,
    'currentTier': None,
    'currentPhase': 'analysis',
    'phaseFlags': {
        'analysisCompleted': False,
        'interviewCompleted': False,
        'planningCompleted': False,
        'taskMgrCompleted': False,
        'workerCompleted': False,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 0, 'completed': [] },
    'reviewTracker': { 'expected': 0, 'completed': [] },
    'workerTracker': { 'expected': 0, 'doneCount': 0 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0 },
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
json_data=$(make_analysis_stop_json "3")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
assert_eq "3a: Tier 3 analysis stop -> workerTracker.expected=1 (default)" "1" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 4: Tier 2 taskmgr overwrites workerTracker.expected
# ─────────────────────────────────────────────────
echo "--- Test Group 4: taskmgr overwrites workerTracker.expected ---"

# 4a: After analysis sets default=1, taskmgr should overwrite with actual count
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 -c "
import json
state = {
    'version': 2,
    'currentTier': 2,
    'currentPhase': 'taskmgr',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': False,
        'workerCompleted': False,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 1, 'completed': ['Planning Agent'] },
    'reviewTracker': { 'expected': 3, 'completed': [] },
    'workerTracker': { 'expected': 1, 'doneCount': 0 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0 },
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
json_data=$(make_taskmgr_stop_json "5")
run_agent_stop "$TEST_ROOT" "$json_data"
actual=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
assert_eq "4a: taskmgr overwrites workerTracker.expected from 1 to 5" "5" "$actual"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 5: taskmgr stop does NOT reset doneCount
# (Verifies redundant doneCount=0 was removed from handle_taskmgr_stop)
# ─────────────────────────────────────────────────
echo "--- Test Group 5: handle_taskmgr_stop does not reset doneCount ---"

# 5a: When doneCount is pre-set to 5, taskmgr stop with WORKER_COUNT:3 should
#     update expected=3 but NOT forcibly reset doneCount back to 0.
#     (After refactor: doneCount is not touched by handle_taskmgr_stop)
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 -c "
import json
state = {
    'version': 2,
    'currentTier': 2,
    'currentPhase': 'taskmgr',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': False,
        'workerCompleted': False,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 1, 'completed': ['Planning Agent'] },
    'reviewTracker': { 'expected': 3, 'completed': [] },
    'workerTracker': { 'expected': 1, 'doneCount': 5 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0 },
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
json_data=$(make_taskmgr_stop_json "3")
run_agent_stop "$TEST_ROOT" "$json_data"
actual_expected=$(read_state_field "$TEST_ROOT" "workerTracker.expected")
actual_done=$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")
assert_eq "5a: taskmgr WORKER_COUNT:3 -> workerTracker.expected=3" "3" "$actual_expected"
assert_eq "5a: taskmgr stop does not reset doneCount (stays 5)" "5" "$actual_done"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 6: activate_rework_if_needed uses state_write for array/bool resets
# (Verifies python3 inline removal didn't break reviewTracker.completed and hasWarnings reset)
# ─────────────────────────────────────────────────
echo "--- Test Group 6: activate_rework_if_needed state_write-based resets ---"

# Helper: create a mock review stop event JSON
make_review_stop_json_local() {
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

# 6a: After rework activation via review completion, reviewTracker.completed == []
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 -c "
import json
state = {
    'version': 2,
    'currentTier': 2,
    'currentPhase': 'review',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': True,
        'qaIntegrationPassed': True,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 1, 'completed': ['Planning Agent'] },
    'reviewTracker': { 'expected': 3, 'completed': ['Security Guardian', 'Quality Inspector'] },
    'workerTracker': { 'expected': 2, 'doneCount': 2 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0, 'hasWarnings': True },
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
json_data=$(make_review_stop_json_local "TDD Enforcer: tdd-check" "All tests pass.")
echo "$json_data" | BATON_ROOT="$TEST_ROOT" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || true
actual=$(read_state_field "$TEST_ROOT" "reviewTracker.completed")
assert_eq "6a: rework activation -> reviewTracker.completed reset to []" "[]" "$actual"
rm -rf "$TEST_ROOT"

# 6b: After rework activation, reworkStatus.hasWarnings == false
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
python3 -c "
import json
state = {
    'version': 2,
    'currentTier': 2,
    'currentPhase': 'review',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': True,
        'qaIntegrationPassed': True,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 1, 'completed': ['Planning Agent'] },
    'reviewTracker': { 'expected': 3, 'completed': ['Security Guardian', 'Quality Inspector'] },
    'workerTracker': { 'expected': 2, 'doneCount': 2 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0, 'hasWarnings': True },
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}
with open('$TEST_ROOT/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
json_data=$(make_review_stop_json_local "TDD Enforcer: tdd-check" "All tests pass.")
echo "$json_data" | BATON_ROOT="$TEST_ROOT" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || true
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_eq "6b: rework activation -> reworkStatus.hasWarnings reset to false" "false" "$actual"
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
