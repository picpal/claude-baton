#!/usr/bin/env bash
# test-main-guard-bash-seal.sh — Tests for main-guard-bash.sh self-sealing control flow
#
# Verifies:
#   1. .agent-stack write → BLOCKED always (even for subagent)
#   2. state.json write, file NOT existing → ALLOWED (init)
#   3. state.json write, file existing, NOT subagent → BLOCKED
#   4. Normal code file write by Main → BLOCKED (existing behavior preserved)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD_SCRIPT="$SCRIPT_DIR/../main-guard-bash.sh"

PASS=0
FAIL=0
TOTAL=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

assert_blocked() {
  local test_name="$1"
  local exit_code="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$exit_code" -eq 2 ]; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name (exit=$exit_code, expected=2)"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (exit=$exit_code, expected=2)"
  fi
}

assert_allowed() {
  local test_name="$1"
  local exit_code="$2"
  TOTAL=$((TOTAL + 1))
  if [ "$exit_code" -eq 0 ]; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name (exit=$exit_code, expected=0)"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (exit=$exit_code, expected=0)"
  fi
}

# Setup temporary .baton environment
setup_env() {
  TEST_BATON_ROOT=$(mktemp -d)
  TEST_BATON_DIR="$TEST_BATON_ROOT/.baton"
  TEST_LOG_DIR="$TEST_BATON_DIR/logs"
  mkdir -p "$TEST_LOG_DIR"
  export BATON_ROOT="$TEST_BATON_ROOT"
}

cleanup_env() {
  rm -rf "$TEST_BATON_ROOT"
  unset BATON_ROOT
}

# Helper: run the guard with a given command, capturing exit code
# $1 = command string to test
# $2 = "subagent" to simulate subagent active, "" otherwise
# $3 = "state_exists" to create state.json before test, "" otherwise
run_guard() {
  local cmd="$1"
  local subagent="${2:-}"
  local state_exists="${3:-}"

  setup_env

  # Optionally create agent-stack (subagent active)
  if [ "$subagent" = "subagent" ]; then
    echo "$(date +%s)|worker-1|task-01" > "$TEST_LOG_DIR/.agent-stack"
  fi

  # Optionally create state.json (already initialized)
  if [ "$state_exists" = "state_exists" ]; then
    echo '{"phase":"analysis"}' > "$TEST_BATON_DIR/state.json"
  fi

  # Build JSON payload matching hook format
  local json
  json=$(python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'PreToolUse',
    'tool_name': 'Bash',
    'session_id': 'test-session',
    'tool_input': {'command': sys.argv[1]}
}, ensure_ascii=False))
" "$cmd")

  local exit_code=0
  echo "$json" | bash "$GUARD_SCRIPT" > /dev/null 2>&1 || exit_code=$?

  cleanup_env
  return $exit_code
}

echo "=== main-guard-bash.sh Self-Sealing Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test 1: .agent-stack write → BLOCKED always
# ─────────────────────────────────────────────────
echo "--- Test Group 1: .agent-stack write → BLOCKED always ---"

# 1a: echo redirect to .agent-stack (no subagent)
exit_code=0
run_guard 'echo "data" > .baton/logs/.agent-stack' "" "" || exit_code=$?
assert_blocked "1a: echo > .agent-stack (Main)" "$exit_code"

# 1b: echo redirect to .agent-stack (WITH subagent active)
exit_code=0
run_guard 'echo "data" > .baton/logs/.agent-stack' "subagent" "" || exit_code=$?
assert_blocked "1b: echo > .agent-stack (subagent active)" "$exit_code"

# 1c: rm .agent-stack
exit_code=0
run_guard 'rm .baton/logs/.agent-stack' "" "" || exit_code=$?
assert_blocked "1c: rm .agent-stack" "$exit_code"

# 1d: tee to .agent-stack
exit_code=0
run_guard 'echo "data" | tee .baton/logs/.agent-stack' "" "" || exit_code=$?
assert_blocked "1d: tee .agent-stack" "$exit_code"

# 1e: sed -i on .agent-stack
exit_code=0
run_guard 'sed -i "" "s/old/new/" .baton/logs/.agent-stack' "" "" || exit_code=$?
assert_blocked "1e: sed -i .agent-stack" "$exit_code"

# 1f: cat (read) .agent-stack → should be ALLOWED
exit_code=0
run_guard 'cat .baton/logs/.agent-stack' "" "" || exit_code=$?
assert_allowed "1f: cat .agent-stack (read only)" "$exit_code"

echo ""

# ─────────────────────────────────────────────────
# Test 2: state.json write, file NOT existing → ALLOWED (init)
# ─────────────────────────────────────────────────
echo "--- Test Group 2: state.json write (NOT existing) → ALLOWED ---"

# 2a: echo redirect to state.json, file does NOT exist
exit_code=0
run_guard 'echo "{}" > .baton/state.json' "" "" || exit_code=$?
assert_allowed "2a: echo > state.json (init, file not exists)" "$exit_code"

# 2b: python write to state.json, file does NOT exist
exit_code=0
run_guard 'python3 -c "open(\".baton/state.json\",\"w\").write(\"{}\")"' "" "" || exit_code=$?
assert_allowed "2b: python write state.json (init, file not exists)" "$exit_code"

echo ""

# ─────────────────────────────────────────────────
# Test 3: state.json write, file existing, NOT subagent → BLOCKED
# ─────────────────────────────────────────────────
echo "--- Test Group 3: state.json write (existing, no subagent) → BLOCKED ---"

# 3a: echo redirect to state.json, file EXISTS
exit_code=0
run_guard 'echo "{}" > .baton/state.json' "" "state_exists" || exit_code=$?
assert_blocked "3a: echo > state.json (exists, Main)" "$exit_code"

# 3b: sed -i on state.json, file EXISTS
exit_code=0
run_guard 'sed -i "" "s/old/new/" .baton/state.json' "" "state_exists" || exit_code=$?
assert_blocked "3b: sed -i state.json (exists, Main)" "$exit_code"

# 3c: rm state.json, file EXISTS
exit_code=0
run_guard 'rm .baton/state.json' "" "state_exists" || exit_code=$?
assert_blocked "3c: rm state.json (exists, Main)" "$exit_code"

# 3d: cat (read) state.json, file EXISTS → ALLOWED
exit_code=0
run_guard 'cat .baton/state.json' "" "state_exists" || exit_code=$?
assert_allowed "3d: cat state.json (read only, exists)" "$exit_code"

echo ""

# ─────────────────────────────────────────────────
# Test 4: Normal code file write by Main → BLOCKED
# ─────────────────────────────────────────────────
echo "--- Test Group 4: Normal code file write by Main → BLOCKED ---"

# 4a: echo redirect to .ts file
exit_code=0
run_guard 'echo "code" > src/index.ts' "" "" || exit_code=$?
assert_blocked "4a: echo > src/index.ts (Main)" "$exit_code"

# 4b: sed -i on .py file
exit_code=0
run_guard 'sed -i "" "s/old/new/" app.py' "" "" || exit_code=$?
assert_blocked "4b: sed -i app.py (Main)" "$exit_code"

# 4c: safe read command → ALLOWED
exit_code=0
run_guard 'cat src/index.ts' "" "" || exit_code=$?
assert_allowed "4c: cat src/index.ts (read only)" "$exit_code"

# 4d: git command → ALLOWED
exit_code=0
run_guard 'git status' "" "" || exit_code=$?
assert_allowed "4d: git status" "$exit_code"

echo ""

# ─────────────────────────────────────────────────
# Test 5: Negative (false-positive) cases — similar filenames must NOT be blocked
# ─────────────────────────────────────────────────
echo "--- Test Group 5: False-positive guard — similar filenames must NOT be blocked ---"

# 5a: backup-state.json write (no subagent, state.json exists) → should NOT hit state.json seal
exit_code=0
run_guard 'echo "{}" > .baton/backup-state.json' "" "state_exists" || exit_code=$?
# Falls into dangerous-write check (exit 2), but must NOT be exit 2 due to state.json seal.
# The seal guard should return 1 (not a state.json match), so either allowed (0)
# or blocked by dangerous-write (2) — but NOT exit 2 due to wrong seal match.
# We verify that is_state_json_write did NOT fire by checking the guard runs the
# full pipeline. We assert it is NOT specifically mis-blocked as state.json (exit 2
# from the seal block has the same code as dangerous-write, so we use a read
# variant to confirm the regex itself doesn't fire).
exit_code=0
run_guard 'cat .baton/backup-state.json' "" "state_exists" || exit_code=$?
assert_allowed "5a: cat backup-state.json (read, state.json exists) — not caught by seal" "$exit_code"

# 5b: state.json.bak write → should NOT be caught by state.json seal
exit_code=0
run_guard 'cat .baton/state.json.bak' "" "state_exists" || exit_code=$?
assert_allowed "5b: cat state.json.bak (read, state.json exists) — not caught by seal" "$exit_code"

# 5c: reference to backup-state.json read → should pass (not .agent-stack)
exit_code=0
run_guard 'cat .baton/logs/my-agent-stack' "" "" || exit_code=$?
assert_allowed "5c: cat my-agent-stack (not .agent-stack) — not blocked" "$exit_code"

# 5d: backup-state.json write inside .baton/ when state.json exists — ALLOWED
#     Writing to .baton/ paths is always allowed; backup-state.json must not be
#     mis-caught by the state.json seal and must not be blocked as dangerous.
exit_code=0
run_guard 'echo "{}" > .baton/backup-state.json' "" "state_exists" || exit_code=$?
assert_allowed "5d: echo > .baton/backup-state.json (state.json exists) — .baton/ write allowed, not mis-sealed" "$exit_code"

echo ""

# ─────────────────────────────────────────────────
# Test 6: False positive prevention — quoted strings must NOT trigger seals
# ─────────────────────────────────────────────────
echo "--- Test Group 6: Quoted string false positive prevention ---"

# 6a: git commit -m "fix: state.json issue" → should NOT be blocked
exit_code=0
run_guard 'git commit -m "fix: state.json issue"' "" "state_exists" || exit_code=$?
assert_allowed "6a: git commit -m 'fix: state.json issue' — quoted string must not trigger state.json seal" "$exit_code"

# 6b: git commit -m "updated .agent-stack logic" → should NOT be blocked
exit_code=0
run_guard 'git commit -m "updated .agent-stack logic"' "" "" || exit_code=$?
assert_allowed "6b: git commit -m 'updated .agent-stack logic' — quoted string must not trigger .agent-stack seal" "$exit_code"

# 6c: echo "state.json" > /tmp/log.txt → should NOT be blocked
#     state.json is inside quotes; actual write target is /tmp/log.txt (safe path)
exit_code=0
run_guard 'echo "state.json" > /tmp/log.txt' "" "state_exists" || exit_code=$?
assert_allowed "6c: echo 'state.json' > /tmp/log.txt — quoted filename must not trigger state.json seal" "$exit_code"

# 6d: echo data > .baton/state.json → should still be BLOCKED (state.json is NOT in quotes)
exit_code=0
run_guard 'echo data > .baton/state.json' "" "state_exists" || exit_code=$?
assert_blocked "6d: echo data > .baton/state.json — unquoted redirect must still be BLOCKED" "$exit_code"

# 6e: cat .baton/state.json → should still be ALLOWED (read, not write)
exit_code=0
run_guard 'cat .baton/state.json' "" "state_exists" || exit_code=$?
assert_allowed "6e: cat .baton/state.json — read-only access must still be ALLOWED" "$exit_code"

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
