#!/usr/bin/env bash
# test-sed-portability.sh — TDD tests for prune_last_line helper and sed -i '' absence
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SCRIPTS="$SCRIPT_DIR/.."

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ─── load prune_last_line ──────────────────────────────────────────────────────
# Source state-manager.sh to get prune_last_line. Override find-baton-root.sh
# side effects with a temp BATON_DIR so state-manager.sh can be sourced safely.
TMP_DIR="$(mktemp -d)"
export BATON_DIR="$TMP_DIR/.baton"
mkdir -p "$BATON_DIR"

# Source state-manager which defines prune_last_line
# shellcheck disable=SC1091
source "$HOOKS_SCRIPTS/state-manager.sh" 2>/dev/null || true

# ─── Test 1: prune_last_line on a 3-line file → 2 lines remaining ─────────────
echo "Test 1: prune_last_line removes last line from 3-line file"
FILE1="$TMP_DIR/file1.txt"
printf 'line1\nline2\nline3\n' > "$FILE1"
prune_last_line "$FILE1"
LINE_COUNT=$(wc -l < "$FILE1" | tr -d ' ')
if [ "$LINE_COUNT" -eq 2 ]; then
  pass "3-line file → 2 lines remaining"
else
  fail "3-line file → expected 2 lines, got $LINE_COUNT"
fi

# Also verify the content (line1 and line2 remain, line3 gone)
if grep -q "line3" "$FILE1"; then
  fail "line3 should have been removed but still present"
else
  pass "line3 was correctly removed"
fi

if grep -q "line1" "$FILE1" && grep -q "line2" "$FILE1"; then
  pass "line1 and line2 are preserved"
else
  fail "line1 or line2 was unexpectedly removed"
fi

# ─── Test 2: prune_last_line on a 1-line file → empty file ───────────────────
echo "Test 2: prune_last_line on a 1-line file → empty file"
FILE2="$TMP_DIR/file2.txt"
printf 'only_line\n' > "$FILE2"
prune_last_line "$FILE2"
if [ -f "$FILE2" ] && [ ! -s "$FILE2" ]; then
  pass "1-line file → file is now empty"
elif [ ! -f "$FILE2" ]; then
  # An empty file may have been deleted - acceptable if file is gone too
  pass "1-line file → file removed (also acceptable)"
else
  REMAINING=$(cat "$FILE2")
  fail "1-line file → expected empty, got: '$REMAINING'"
fi

# ─── Test 3: prune_last_line on missing file → no error (returns 0) ──────────
echo "Test 3: prune_last_line on missing file → no error"
MISSING="$TMP_DIR/does_not_exist.txt"
if prune_last_line "$MISSING"; then
  pass "missing file → returns 0 (no error)"
else
  fail "missing file → returned non-zero exit code"
fi

# ─── Test 4: Grep guard — no sed -i '' in production scripts ─────────────────
echo "Test 4: no 'sed -i' in production scripts"
PRODUCTION_SCRIPTS=(
  "state-manager.sh"
  "agent-logger.sh"
  "on-stop-failure.sh"
  "regress-to-phase.sh"
  "phase-gate.sh"
  "security-halt.sh"
  "verify-before-commit.sh"
  "main-guard.sh"
  "main-guard-bash.sh"
  "find-baton-root.sh"
)

FOUND_SED=0
for script in "${PRODUCTION_SCRIPTS[@]}"; do
  SCRIPT_PATH="$HOOKS_SCRIPTS/$script"
  if [ ! -f "$SCRIPT_PATH" ]; then
    # File doesn't exist — skip (not a failure)
    continue
  fi
  if grep -n "sed -i ''" "$SCRIPT_PATH" 2>/dev/null; then
    fail "sed -i '' found in $script"
    FOUND_SED=1
  fi
done
if [ "$FOUND_SED" -eq 0 ]; then
  pass "no 'sed -i \\'\\'' found in any production script"
fi

# ─── Cleanup ─────────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"

# ─── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
