#!/usr/bin/env bash
# test-user-prompt-submit-tracker.sh — Tests for tracker progress display in user-prompt-submit.sh
#
# Verifies:
#   1. No state.json → output shows only todo.md counts (DONE/TOTAL)
#   2. phase=review, reviewTracker populated → output includes rev(D/E)
#   3. phase=worker, workerTracker populated → output includes wrk(D/E)
#   4. phase=planning, planningTracker populated → output includes pln(D/E)
#   5. phase=review, expected=0 → TRACKER_PROGRESS empty → output shows only DONE/TOTAL
#   6. state_array_len function exists in state-manager.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../user-prompt-submit.sh"
STATE_MANAGER="$SCRIPT_DIR/../state-manager.sh"

PASS=0
FAIL=0
TOTAL_TESTS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_contains() {
  local test_name="$1"
  local output="$2"
  local expected="$3"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if echo "$output" | grep -qF "$expected"; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name"
    echo "  Expected to find: '$expected'"
    echo "  In output: '$output'"
  fi
}

assert_not_contains() {
  local test_name="$1"
  local output="$2"
  local unexpected="$3"
  TOTAL_TESTS=$((TOTAL_TESTS + 1))
  if ! echo "$output" | grep -qF "$unexpected"; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name"
    echo "  Expected NOT to find: '$unexpected'"
    echo "  In output: '$output'"
  fi
}

# Helper: write state.json with tracker data
write_state_with_trackers() {
  local dir="$1"
  local tier="$2"
  local phase="$3"
  local review_expected="${4:-0}"
  local review_completed="${5:-[]}"
  local worker_expected="${6:-0}"
  local worker_done="${7:-0}"
  local planning_expected="${8:-0}"
  local planning_completed="${9:-[]}"

  python3 -c "
import json, os

tier_val = None if '$tier' == 'null' else int('$tier')
phase_val = '$phase'
review_expected = $review_expected
review_completed = $review_completed
worker_expected = $worker_expected
worker_done = $worker_done
planning_expected = $planning_expected
planning_completed = $planning_completed

state = {
    'version': 2,
    'currentTier': tier_val,
    'currentPhase': phase_val,
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
    'planningTracker': {'expected': planning_expected, 'completed': planning_completed},
    'reviewTracker': {'expected': review_expected, 'completed': review_completed},
    'workerTracker': {'expected': worker_expected, 'doneCount': worker_done},
    'qaRetryCount': {},
    'reworkStatus': {'active': False, 'attemptCount': 0},
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}

with open('$dir/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
}

# Helper: write todo.md with some tasks
write_todo() {
  local dir="$1"
  local total="${2:-5}"
  local done="${3:-2}"
  python3 -c "
total = $total
done = $done
lines = []
for i in range(total):
    if i < done:
        lines.append('- [x] task-{:02d}: done task'.format(i+1))
    else:
        lines.append('- [ ] task-{:02d}: pending task'.format(i+1))
print('\n'.join(lines))
" > "$dir/todo.md"
}

# Helper: run the hook and capture output
run_hook() {
  local baton_root="$1"
  local prompt="${2:-continue}"
  local output=""
  local json
  json=$(python3 -c "
import json
print(json.dumps({
    'hook_event_name': 'UserPromptSubmit',
    'session_id': 'test-session',
    'user_prompt': '$prompt'
}))
")
  output=$(echo "$json" | BATON_ROOT="$baton_root" bash "$HOOK_SCRIPT" 2>/dev/null || true)
  echo "$output"
}

echo "=== user-prompt-submit.sh Tracker Progress Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test 1: state_array_len function exists in state-manager.sh
# ─────────────────────────────────────────────────
echo "--- Test 1: state_array_len function exists ---"
TOTAL_TESTS=$((TOTAL_TESTS + 1))
if grep -q "state_array_len" "$STATE_MANAGER"; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: state_array_len is defined in state-manager.sh"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: state_array_len is NOT defined in state-manager.sh"
fi
echo ""

# ─────────────────────────────────────────────────
# Test 2: No state.json → only DONE/TOTAL shown
# ─────────────────────────────────────────────────
echo "--- Test 2: No state.json → only DONE/TOTAL counts shown ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
output=$(run_hook "$TEST_ROOT")
assert_contains "2a: output contains [Baton]" "$output" "[Baton]"
assert_not_contains "2b: no tracker prefix (rev/wrk/pln) when no state.json" "$output" "rev("
assert_not_contains "2c: no tracker prefix (wrk) when no state.json" "$output" "wrk("
assert_not_contains "2d: no tracker prefix (pln) when no state.json" "$output" "pln("
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 3: phase=review, reviewTracker populated → rev(D/E) shown
# ─────────────────────────────────────────────────
echo "--- Test 3: phase=review with reviewTracker → rev(1/3) shown ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "review" 3 '["reviewer-1"]' 0 0 0 '[]'
output=$(run_hook "$TEST_ROOT")
assert_contains "3a: output contains rev(1/3)" "$output" "rev(1/3)"
assert_contains "3b: output also contains todo counts 2/5" "$output" "2/5"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 4: phase=worker, workerTracker populated → wrk(D/E) shown
# ─────────────────────────────────────────────────
echo "--- Test 4: phase=worker with workerTracker → wrk(3/5) shown ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "worker" 0 '[]' 5 3 0 '[]'
output=$(run_hook "$TEST_ROOT")
assert_contains "4a: output contains wrk(3/5)" "$output" "wrk(3/5)"
assert_contains "4b: output also contains todo counts 2/5" "$output" "2/5"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 5: phase=planning, planningTracker populated → pln(D/E) shown
# ─────────────────────────────────────────────────
echo "--- Test 5: phase=planning with planningTracker → pln(2/3) shown ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "planning" 0 '[]' 0 0 3 '["planner-1","planner-2"]'
output=$(run_hook "$TEST_ROOT")
assert_contains "5a: output contains pln(2/3)" "$output" "pln(2/3)"
assert_contains "5b: output also contains todo counts 2/5" "$output" "2/5"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 6: phase=review, expected=0 → no tracker prefix shown
# ─────────────────────────────────────────────────
echo "--- Test 6: phase=review, expected=0 → no tracker prefix ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "review" 0 '[]' 0 0 0 '[]'
output=$(run_hook "$TEST_ROOT")
assert_not_contains "6a: no rev() when expected=0" "$output" "rev("
assert_contains "6b: still shows todo counts 2/5" "$output" "2/5"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 7: phase=review with 0 completed → rev(0/3)
# ─────────────────────────────────────────────────
echo "--- Test 7: phase=review, completed=[], expected=3 → rev(0/3) shown ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 0
write_state_with_trackers "$TEST_BATON" "2" "review" 3 '[]' 0 0 0 '[]'
output=$(run_hook "$TEST_ROOT")
assert_contains "7a: output contains rev(0/3)" "$output" "rev(0/3)"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Helpers for stale-stack tests
# ─────────────────────────────────────────────────
now_ts() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

stale_ts() {
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(hours=3)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

old_ts_1s() {
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=5)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

# ─────────────────────────────────────────────────
# Test 8: Empty stack → no warning line, normal output
# ─────────────────────────────────────────────────
echo "--- Test 8: Empty .agent-stack → no stale warning, normal output ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "idle" 0 '[]' 0 0 0 '[]'
# agent-stack does not exist (or is empty)
output=$(run_hook "$TEST_ROOT")
assert_not_contains "8a: no stale warning when stack is empty" "$output" "[Baton] ⚠ Cleaned"
assert_contains "8b: normal statusline still present" "$output" "[Baton]"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 9: Stack with 3 zombies → warning shown with count, then normal output
# ─────────────────────────────────────────────────
echo "--- Test 9: Stack with 3 zombie entries → warning with count, normal statusline ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "idle" 0 '[]' 0 0 0 '[]'
FRESH=$(now_ts)
STALE=$(stale_ts)
STACK="$TEST_BATON/logs/.agent-stack"
# 3 zombie entries: 2 empty-name + 1 stale TTL
printf '%s|\n' "$FRESH" >> "$STACK"
printf '%s|\n' "$FRESH" >> "$STACK"
printf '%s|claude-baton:old-worker\n' "$STALE" >> "$STACK"
output=$(run_hook "$TEST_ROOT")
assert_contains "9a: stale warning with count 3" "$output" "[Baton] ⚠ Cleaned 3 stale agent-stack entries (TTL=2h)"
assert_contains "9b: normal [Baton] statusline still present after warning" "$output" "idle"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 10: Mixed stack → only zombies removed, valid kept, count in warning
# ─────────────────────────────────────────────────
echo "--- Test 10: Mixed stack → 1 zombie removed, 2 valid kept, warning shows count 1 ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "idle" 0 '[]' 0 0 0 '[]'
FRESH=$(now_ts)
STACK="$TEST_BATON/logs/.agent-stack"
# 1 zombie + 2 valid fresh entries
printf '%s|\n' "$FRESH" >> "$STACK"
printf '%s|claude-baton:worker-agent\n' "$FRESH" >> "$STACK"
printf '%s|claude-baton:qa-unit\n' "$FRESH" >> "$STACK"
output=$(run_hook "$TEST_ROOT")
assert_contains "10a: warning shows count 1 for single zombie" "$output" "[Baton] ⚠ Cleaned 1 stale agent-stack entries (TTL=2h)"
assert_contains "10b: normal statusline present" "$output" "[Baton]"
# Confirm valid entries still remain (stack file has 2 lines)
TOTAL_TESTS=$((TOTAL_TESTS + 1))
remaining=$(wc -l < "$STACK" | tr -d ' ')
if [ "$remaining" = "2" ]; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 10c: 2 valid entries remain in stack file"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 10c: 2 valid entries remain in stack file (expected=2, actual=$remaining)"
fi
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test 11: STACK_TTL_SECONDS=1 with old entry → removed and warned
# ─────────────────────────────────────────────────
echo "--- Test 11: STACK_TTL_SECONDS=1, old entry (5s) → removed and warning shown ---"
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_todo "$TEST_BATON" 5 2
write_state_with_trackers "$TEST_BATON" "2" "idle" 0 '[]' 0 0 0 '[]'
OLD=$(old_ts_1s)
STACK="$TEST_BATON/logs/.agent-stack"
printf '%s|claude-baton:worker-agent\n' "$OLD" >> "$STACK"
# run_hook_with_ttl: same as run_hook but passes STACK_TTL_SECONDS env var
json11=$(python3 -c "
import json
print(json.dumps({
    'hook_event_name': 'UserPromptSubmit',
    'session_id': 'test-session',
    'user_prompt': 'continue'
}))
")
output=$(echo "$json11" | BATON_ROOT="$TEST_ROOT" STACK_TTL_SECONDS=1 bash "$HOOK_SCRIPT" 2>/dev/null || true)
assert_contains "11a: TTL=1 expired entry → warning shown" "$output" "[Baton] ⚠ Cleaned 1 stale agent-stack entries (TTL=2h)"
assert_contains "11b: normal statusline present after warning" "$output" "[Baton]"
rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
echo "=== Summary ==="
echo "Total: $TOTAL_TESTS  Pass: $PASS  Fail: $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}SOME TESTS FAILED${NC}"
  exit 1
else
  echo -e "${GREEN}ALL TESTS PASSED${NC}"
  exit 0
fi
