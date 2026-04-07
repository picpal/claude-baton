#!/usr/bin/env bash
# test-on-stop-failure-pop.sh — Tests for on-stop-failure.sh safe agent_type pop
#
# Verifies:
#   1. Stack [worker, security-guardian, qa-unit] → STOP_FAILURE agent_type=security-guardian
#      → only security-guardian removed, others intact
#   2. Stack 3 entries → no agent_type in payload → stack untouched, warning logged
#   3. Stack 3 entries → agent_type=nonexistent → stack untouched, warning logged
#   4. Stack 2 worker-agent entries → agent_type=worker-agent → LAST one removed (LIFO)
#   5. Empty stack → no crash, no error
#   6. STOP_FAILURE event always logged to exec.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../on-stop-failure.sh"

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
    echo -e "${GREEN}PASS${NC}: $test_name (expected='$expected')"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (expected='$expected', actual='$actual')"
  fi
}

assert_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name (contains '$needle')"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (expected to contain '$needle', got: '$haystack')"
  fi
}

# Helper: create a fresh baton test environment
make_test_env() {
  local TEST_ROOT
  TEST_ROOT=$(mktemp -d)
  mkdir -p "$TEST_ROOT/.baton/logs"
  echo "$TEST_ROOT"
}

# Helper: fresh ISO8601 UTC timestamp
now_ts() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Helper: run hook with a JSON payload (via stdin)
run_hook() {
  local test_root="$1"
  local payload="$2"
  BATON_ROOT="$test_root" bash -c "echo '$payload' | bash '$HOOK_SCRIPT'" 2>/dev/null
}

echo "=== on-stop-failure.sh Safe Pop Tests ==="
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test 1: Stack [worker, security-guardian, qa-unit] → agent_type=security-guardian
#         → only security-guardian removed, others intact
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test 1: Match by agent_type — only matching entry removed ---"

TEST_ROOT=$(make_test_env)
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"
TS=$(now_ts)

printf '%s|claude-baton:worker-agent\n' "$TS" >> "$STACK_FILE"
printf '%s|claude-baton:security-guardian\n' "$TS" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$TS" >> "$STACK_FILE"

PAYLOAD='{"hook_event_name":"StopFailure","agent_type":"claude-baton:security-guardian"}'
run_hook "$TEST_ROOT" "$PAYLOAD"

# security-guardian should be removed
remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "1a: 2 entries remain after removing security-guardian" "2" "$remaining"

has_worker=$(grep -c "worker-agent" "$STACK_FILE" 2>/dev/null; true)
assert_eq "1b: worker-agent still in stack" "1" "$has_worker"

has_qa=$(grep -c "qa-unit" "$STACK_FILE" 2>/dev/null; true)
assert_eq "1c: qa-unit still in stack" "1" "$has_qa"

has_guardian=$(grep -c "security-guardian" "$STACK_FILE" 2>/dev/null; true)
assert_eq "1d: security-guardian removed from stack" "0" "$has_guardian"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test 2: Stack 3 entries → no agent_type in payload → stack untouched, warning logged
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test 2: No agent_type in payload → stack untouched, warning logged ---"

TEST_ROOT=$(make_test_env)
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"
LOG_FILE="$TEST_ROOT/.baton/logs/exec.log"
TS=$(now_ts)

printf '%s|claude-baton:worker-agent\n' "$TS" >> "$STACK_FILE"
printf '%s|claude-baton:security-guardian\n' "$TS" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$TS" >> "$STACK_FILE"

# Payload without agent_type field
PAYLOAD='{"hook_event_name":"StopFailure"}'
run_hook "$TEST_ROOT" "$PAYLOAD"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "2a: all 3 entries intact when no agent_type" "3" "$remaining"

# exec.log should have a STOP_FAILURE_WARNING entry
if [ -f "$LOG_FILE" ]; then
  log_content=$(cat "$LOG_FILE")
else
  log_content=""
fi
assert_contains "2b: STOP_FAILURE_WARNING logged when no agent_type" "STOP_FAILURE_WARNING" "$log_content"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test 3: Stack 3 entries → agent_type=nonexistent → stack untouched, warning logged
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test 3: agent_type not found in stack → stack untouched, warning logged ---"

TEST_ROOT=$(make_test_env)
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"
LOG_FILE="$TEST_ROOT/.baton/logs/exec.log"
TS=$(now_ts)

printf '%s|claude-baton:worker-agent\n' "$TS" >> "$STACK_FILE"
printf '%s|claude-baton:security-guardian\n' "$TS" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$TS" >> "$STACK_FILE"

PAYLOAD='{"hook_event_name":"StopFailure","agent_type":"claude-baton:nonexistent-agent"}'
run_hook "$TEST_ROOT" "$PAYLOAD"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "3a: all 3 entries intact when agent_type not found" "3" "$remaining"

if [ -f "$LOG_FILE" ]; then
  log_content=$(cat "$LOG_FILE")
else
  log_content=""
fi
assert_contains "3b: STOP_FAILURE_WARNING logged when agent_type not found" "STOP_FAILURE_WARNING" "$log_content"
assert_contains "3c: not_in_stack reason in warning" "not_in_stack" "$log_content"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test 4: Stack 2 worker-agent entries → agent_type=worker-agent → LAST one removed (LIFO)
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test 4: 2 identical agent_type entries → LAST one removed (LIFO) ---"

TEST_ROOT=$(make_test_env)
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"
TS=$(now_ts)

# First entry uses slightly different marker text to distinguish
printf '2026-01-01T00:00:00Z|claude-baton:worker-agent\n' >> "$STACK_FILE"
printf '%s|claude-baton:worker-agent\n' "$TS" >> "$STACK_FILE"

PAYLOAD='{"hook_event_name":"StopFailure","agent_type":"claude-baton:worker-agent"}'
run_hook "$TEST_ROOT" "$PAYLOAD"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "4a: 1 entry remains after removing last worker-agent" "1" "$remaining"

# The FIRST (oldest) entry should remain, not the last
first_line=$(head -1 "$STACK_FILE")
assert_contains "4b: older entry (first line) is preserved" "2026-01-01T00:00:00Z" "$first_line"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test 5: Empty stack → no crash, no error
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test 5: Empty stack → no crash, exits 0 ---"

TEST_ROOT=$(make_test_env)
# No stack file created — test that hook doesn't crash

PAYLOAD='{"hook_event_name":"StopFailure","agent_type":"claude-baton:worker-agent"}'
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "echo '$PAYLOAD' | bash '$HOOK_SCRIPT'" 2>/dev/null || exit_code=$?

assert_eq "5a: hook exits 0 when stack file missing" "0" "$exit_code"

# Verify log file was created (STOP_FAILURE always logged)
LOG_FILE="$TEST_ROOT/.baton/logs/exec.log"
if [ -f "$LOG_FILE" ]; then
  log_exists="true"
else
  log_exists="false"
fi
assert_eq "5b: exec.log created even with empty stack" "true" "$log_exists"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test 6: STOP_FAILURE event always logged to exec.log
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test 6: STOP_FAILURE always logged to exec.log ---"

# 6a: Successful pop also logs STOP_FAILURE event
TEST_ROOT=$(make_test_env)
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"
LOG_FILE="$TEST_ROOT/.baton/logs/exec.log"
TS=$(now_ts)

printf '%s|claude-baton:worker-agent\n' "$TS" >> "$STACK_FILE"

PAYLOAD='{"hook_event_name":"StopFailure","agent_type":"claude-baton:worker-agent"}'
run_hook "$TEST_ROOT" "$PAYLOAD"

if [ -f "$LOG_FILE" ]; then
  log_content=$(cat "$LOG_FILE")
else
  log_content=""
fi
assert_contains "6a: STOP_FAILURE logged on successful pop" "STOP_FAILURE" "$log_content"
assert_contains "6b: STACK_POP logged on successful match" "STACK_POP" "$log_content"

rm -rf "$TEST_ROOT"

# 6b: No agent_type → STOP_FAILURE still logged
TEST_ROOT=$(make_test_env)
LOG_FILE="$TEST_ROOT/.baton/logs/exec.log"

PAYLOAD='{"hook_event_name":"StopFailure"}'
run_hook "$TEST_ROOT" "$PAYLOAD"

if [ -f "$LOG_FILE" ]; then
  log_content=$(cat "$LOG_FILE")
else
  log_content=""
fi
assert_contains "6c: STOP_FAILURE logged even with no agent_type" "STOP_FAILURE" "$log_content"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
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
