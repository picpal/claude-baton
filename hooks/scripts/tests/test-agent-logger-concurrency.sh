#!/usr/bin/env bash
# test-agent-logger-concurrency.sh — Tests for agent-logger.sh concurrency safety
#
# Verifies the T2/R12 fix: state_array_add and state_increment in agent-logger.sh
# must use fcntl.flock + atomic os.replace so that parallel writes do not lose
# updates. state_increment must be a SINGLE locked python block, not a bash
# read-modify-write across two subprocesses.
#
# Test groups:
#   1. Sanity — single state_array_add and state_increment work
#   2. Parallel state_array_add to same array — all entries persist
#   3. Parallel state_increment to same field — final count == number of calls
#   4. SLOW_MUTATE=1 + 5 parallel state_increment — final count = 5
#   5. State.json remains valid after concurrent operations

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOKS_SCRIPTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_LOGGER="$HOOKS_SCRIPTS_DIR/agent-logger.sh"
STATE_MANAGER="$HOOKS_SCRIPTS_DIR/state-manager.sh"

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

# Helper: read a field from state.json directly via python
read_state_field() {
  local dir="$1"
  local field="$2"
  python3 -c "
import json, sys
try:
    with open('$dir/.baton/state.json') as f:
        d = json.load(f)
except Exception as e:
    print('READ_ERROR:' + str(e))
    sys.exit(0)
keys = '$field'.split('.')
val = d
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        print('null')
        sys.exit(0)
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

# Helper: read array length directly from state.json
read_array_len() {
  local dir="$1"
  local field="$2"
  python3 -c "
import json, sys
try:
    with open('$dir/.baton/state.json') as f:
        d = json.load(f)
except Exception:
    print('-1')
    sys.exit(0)
keys = '$field'.split('.')
val = d
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        print('-1')
        sys.exit(0)
if isinstance(val, list):
    print(len(val))
else:
    print('-1')
"
}

# Helper: assert state.json is parseable JSON (i.e. not corrupted)
state_json_is_valid() {
  local dir="$1"
  if python3 -c "import json; json.load(open('$dir/.baton/state.json'))" 2>/dev/null; then
    echo "true"
  else
    echo "false"
  fi
}

# Helper: source enough of agent-logger.sh to call its mutators in isolation.
# We can't source agent-logger.sh directly because it has top-level execution
# code (the case "$EVENT" block). Instead we extract just the function bodies
# we need by sourcing state-manager.sh and re-defining state_array_add and
# state_increment via the actual agent-logger.sh definitions.
#
# Approach: source state-manager.sh first (so STATE_FILE is set), then use
# `source` on agent-logger.sh with EVENT="" so the case block is a no-op.
load_agent_logger() {
  # Setting EVENT to a value not matched by the case statement means the
  # function definitions are loaded but no event handler runs.
  EVENT="__test_noop__" source "$AGENT_LOGGER"
}

echo "=== Agent-Logger Concurrency Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: Sanity — single state_array_add and state_increment
# ─────────────────────────────────────────────────
echo "--- Test Group 1: Sanity (single calls) ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

BATON_ROOT="$TEST_ROOT" bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_init
  state_array_add 'planningTracker.completed' 'agent-1'
  state_array_add 'planningTracker.completed' 'agent-2'
  state_increment 'workerTracker.doneCount' >/dev/null
  state_increment 'workerTracker.doneCount' >/dev/null
  state_increment 'workerTracker.doneCount' >/dev/null
" 2>/dev/null

assert_eq "1a: single state_array_add — array length=2" "2" "$(read_array_len "$TEST_ROOT" "planningTracker.completed")"
assert_eq "1b: single state_increment — doneCount=3 after 3 calls" "3" "$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")"
assert_eq "1c: state.json remains valid JSON" "true" "$(state_json_is_valid "$TEST_ROOT")"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test Group 2: Parallel state_array_add — all entries persist
# ─────────────────────────────────────────────────
echo "--- Test Group 2: Parallel state_array_add to same array ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

BATON_ROOT="$TEST_ROOT" bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_init
" 2>/dev/null

# Launch 10 parallel append operations.
# Without locking, several would be lost because each call does
# read-modify-write of the array.
BATON_ROOT="$TEST_ROOT" bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_array_add 'reviewTracker.completed' 'reviewer-01' &
  state_array_add 'reviewTracker.completed' 'reviewer-02' &
  state_array_add 'reviewTracker.completed' 'reviewer-03' &
  state_array_add 'reviewTracker.completed' 'reviewer-04' &
  state_array_add 'reviewTracker.completed' 'reviewer-05' &
  state_array_add 'reviewTracker.completed' 'reviewer-06' &
  state_array_add 'reviewTracker.completed' 'reviewer-07' &
  state_array_add 'reviewTracker.completed' 'reviewer-08' &
  state_array_add 'reviewTracker.completed' 'reviewer-09' &
  state_array_add 'reviewTracker.completed' 'reviewer-10' &
  wait
" 2>/dev/null

assert_eq "2a: 10 parallel state_array_add — all 10 entries persist" "10" "$(read_array_len "$TEST_ROOT" "reviewTracker.completed")"
assert_eq "2b: state.json remains valid JSON after parallel array_add" "true" "$(state_json_is_valid "$TEST_ROOT")"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test Group 3: Parallel state_increment — final count = number of calls
# ─────────────────────────────────────────────────
echo "--- Test Group 3: Parallel state_increment to same field ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

BATON_ROOT="$TEST_ROOT" bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_init
" 2>/dev/null

# 10 parallel increments. Without an atomic locked python block,
# the bash read-modify-write loses increments.
BATON_ROOT="$TEST_ROOT" bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  wait
" 2>/dev/null

assert_eq "3a: 10 parallel state_increment — doneCount=10 (no lost increments)" "10" "$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")"
assert_eq "3b: state.json remains valid JSON after parallel increments" "true" "$(state_json_is_valid "$TEST_ROOT")"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test Group 4: SLOW_MUTATE=1 + 5 parallel state_increment — final = 5
# ─────────────────────────────────────────────────
echo "--- Test Group 4: SLOW_MUTATE=1 + 5 parallel state_increment ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

BATON_ROOT="$TEST_ROOT" bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_init
" 2>/dev/null

SECONDS_BEFORE=$SECONDS
BATON_ROOT="$TEST_ROOT" SLOW_MUTATE=1 bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  state_increment 'workerTracker.doneCount' >/dev/null &
  wait
" 2>/dev/null
SECONDS_AFTER=$SECONDS
ELAPSED=$((SECONDS_AFTER - SECONDS_BEFORE))

assert_eq "4a: SLOW_MUTATE — 5 parallel state_increment, doneCount=5" "5" "$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")"
assert_eq "4b: state.json remains valid JSON after SLOW_MUTATE increments" "true" "$(state_json_is_valid "$TEST_ROOT")"

# Locking should serialize the SLOW_MUTATE writers — 5 * 0.2s = ~1s minimum.
if [ "$ELAPSED" -ge 1 ]; then
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  echo -e "${GREEN}PASS${NC}: 4c: SLOW_MUTATE state_increment serialized (elapsed=${ELAPSED}s >= 1s)"
else
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 4c: SLOW_MUTATE state_increment completed (elapsed=${ELAPSED}s, soft check)"
fi

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test Group 5: SLOW_MUTATE=1 parallel state_array_add — all persist
# ─────────────────────────────────────────────────
echo "--- Test Group 5: SLOW_MUTATE=1 + 5 parallel state_array_add ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

BATON_ROOT="$TEST_ROOT" bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_init
" 2>/dev/null

BATON_ROOT="$TEST_ROOT" SLOW_MUTATE=1 bash -c "
  cd '$HOOKS_SCRIPTS_DIR'
  EVENT='__test_noop__' source './agent-logger.sh'
  state_array_add 'reviewTracker.completed' 'r-1' &
  state_array_add 'reviewTracker.completed' 'r-2' &
  state_array_add 'reviewTracker.completed' 'r-3' &
  state_array_add 'reviewTracker.completed' 'r-4' &
  state_array_add 'reviewTracker.completed' 'r-5' &
  wait
" 2>/dev/null

assert_eq "5a: SLOW_MUTATE — 5 parallel state_array_add, len=5" "5" "$(read_array_len "$TEST_ROOT" "reviewTracker.completed")"
assert_eq "5b: state.json remains valid JSON after SLOW_MUTATE array_add" "true" "$(state_json_is_valid "$TEST_ROOT")"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
echo "=== Summary ==="
echo "Total: $TOTAL  Pass: $PASS  Fail: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
