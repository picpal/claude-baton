#!/usr/bin/env bash
# test-main-guard-seal.sh — state.json self-sealing guard tests
# Tests the self-sealing behavior of state.json and the permanent block on .agent-stack

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/../main-guard.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Helper: run guard with a given file_path and BATON_ROOT override
# Returns exit code of the guard as a plain integer on stdout
run_guard() {
  local file_path="$1"
  local baton_root="$2"
  local json
  json=$(printf '{"tool_input":{"file_path":"%s"}}' "$file_path")

  # Use a temp file so we can capture the exit code cleanly
  local exit_code_file
  exit_code_file=$(mktemp)

  (
    export BATON_ROOT="$baton_root"
    printf '%s' "$json" | bash "$GUARD" >/dev/null 2>&1
    printf '%s' $? > "$exit_code_file"
  )

  local code
  code=$(cat "$exit_code_file")
  rm -f "$exit_code_file"
  echo "$code"
}

# ────────────────────────────────────────────────────────────
# Setup: isolated temp project directory
# ────────────────────────────────────────────────────────────
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PROJECT="$TMPDIR_ROOT/project"
mkdir -p "$PROJECT/.baton/logs"

# ────────────────────────────────────────────────────────────
# Test 1: state.json — does NOT exist → ALLOW (exit 0)
# ────────────────────────────────────────────────────────────
echo ""
echo "Test 1: state.json does not exist → should be ALLOWED (exit 0)"
rm -f "$PROJECT/.baton/state.json"

RESULT=$(run_guard "$PROJECT/.baton/state.json" "$PROJECT")
if [ "$RESULT" = "0" ]; then
  pass "state.json (no file) → exit 0 (allowed)"
else
  fail "state.json (no file) → got exit $RESULT, expected 0"
fi

# ────────────────────────────────────────────────────────────
# Test 2: state.json — EXISTS → BLOCK (exit 1 or 2)
# ────────────────────────────────────────────────────────────
echo ""
echo "Test 2: state.json exists → should be BLOCKED (exit 1 or 2)"
echo '{"phase":"done"}' > "$PROJECT/.baton/state.json"

RESULT=$(run_guard "$PROJECT/.baton/state.json" "$PROJECT")
if [ "$RESULT" = "1" ] || [ "$RESULT" = "2" ]; then
  pass "state.json (file exists) → exit $RESULT (blocked)"
else
  fail "state.json (file exists) → got exit $RESULT, expected 1 or 2"
fi

# ────────────────────────────────────────────────────────────
# Test 3: .agent-stack — ALWAYS blocked (exit 1 or 2)
# ────────────────────────────────────────────────────────────
echo ""
echo "Test 3: .agent-stack → should ALWAYS be BLOCKED (exit 1 or 2)"

RESULT=$(run_guard "$PROJECT/.baton/logs/.agent-stack" "$PROJECT")
if [ "$RESULT" = "1" ] || [ "$RESULT" = "2" ]; then
  pass ".agent-stack → exit $RESULT (blocked)"
else
  fail ".agent-stack → got exit $RESULT, expected 1 or 2"
fi

# ────────────────────────────────────────────────────────────
# Test 4: backup-state.json — should NOT be blocked (false-positive check)
# ────────────────────────────────────────────────────────────
echo ""
echo "Test 4: backup-state.json → should NOT be blocked (exits as normal code file)"
echo '{"phase":"done"}' > "$PROJECT/.baton/state.json"

RESULT=$(run_guard "$PROJECT/.baton/backup-state.json" "$PROJECT")
# Guard falls through to the "Main direct edit" block (exit 2), but must NOT
# be caught by the state.json sealed-file branch (exit 1).
if [ "$RESULT" != "1" ]; then
  pass "backup-state.json → not caught by state.json seal (exit $RESULT)"
else
  fail "backup-state.json → wrongly caught by state.json seal (exit $RESULT)"
fi

# ────────────────────────────────────────────────────────────
# Test 5: state.json.bak — should NOT be blocked by state.json seal
# ────────────────────────────────────────────────────────────
echo ""
echo "Test 5: state.json.bak → should NOT be blocked by state.json seal"

RESULT=$(run_guard "$PROJECT/.baton/state.json.bak" "$PROJECT")
if [ "$RESULT" != "1" ]; then
  pass "state.json.bak → not caught by state.json seal (exit $RESULT)"
else
  fail "state.json.bak → wrongly caught by state.json seal (exit $RESULT)"
fi

# ────────────────────────────────────────────────────────────
# Test 6: my-agent-stack (not .agent-stack) — should NOT be blocked
# ────────────────────────────────────────────────────────────
echo ""
echo "Test 6: my-agent-stack → should NOT be blocked by .agent-stack rule"

RESULT=$(run_guard "$PROJECT/.baton/logs/my-agent-stack" "$PROJECT")
if [ "$RESULT" != "1" ]; then
  pass "my-agent-stack → not caught by .agent-stack block (exit $RESULT)"
else
  fail "my-agent-stack → wrongly caught by .agent-stack block (exit $RESULT)"
fi

# ────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "────────────────────────────────"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
