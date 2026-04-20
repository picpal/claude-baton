#!/usr/bin/env bash
# test-main-guard.sh — Tests for relaxed Main Orchestrator whitelist
#
# Verifies that main-guard.sh:
#   1. Keeps existing whitelist (.baton/, .claude/, CLAUDE.md, .gitignore) unlimited
#   2. Keeps subagent-active pass-through
#   3. Adds a root-level config/README whitelist with a ≤20-line diff cap
#   4. Blocks lockfiles (any path) with reason `lockfile-excluded`
#   5. Blocks pipeline-definition trees (agents/commands/skills/hooks) with
#      reason `pipeline-def-excluded`
#   6. Blocks nested json (non-root) even though root jsons are allowed
#   7. Blocks source trees (src/test/tests/lib) — existing behavior preserved

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GUARD="$SCRIPT_DIR/../main-guard.sh"

PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────

# Run the guard with JSON built from a Python dict.
#   $1 = BATON_ROOT override (project dir with .baton/)
#   $2 = subagent_active  ("subagent" to populate .agent-stack, "" otherwise)
#   $3 = python literal producing the JSON payload
# Returns: "<exit_code>|<stdout+stderr>" (separator is a literal pipe)
run_guard_json() {
  local baton_root="$1"
  local subagent="$2"
  local py_json="$3"

  local log_dir="$baton_root/.baton/logs"
  mkdir -p "$log_dir"
  if [ "$subagent" = "subagent" ]; then
    echo "$(date +%s)|worker-1|task-01" > "$log_dir/.agent-stack"
  else
    rm -f "$log_dir/.agent-stack"
  fi

  local json
  json=$(python3 -c "
import json
$py_json
print(json.dumps(payload, ensure_ascii=False))
")

  local out exit_code
  out=$(BATON_ROOT="$baton_root" bash "$GUARD" <<<"$json" 2>&1)
  exit_code=$?
  # Use a rare separator to preserve multi-line output
  printf '%s\n---EXIT---\n%s' "$exit_code" "$out"
}

# Convenience: extract exit code / output from run_guard_json result
extract_code() { echo "$1" | sed -n '1p'; }
extract_out()  { echo "$1" | sed -e '1,/^---EXIT---$/d'; }

# ─────────────────────────────────────────────────────────────
# Setup: isolated temp project
# ─────────────────────────────────────────────────────────────
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PROJECT="$TMPDIR_ROOT/project"
mkdir -p "$PROJECT/.baton/logs"

echo "=== main-guard.sh relaxed-whitelist tests ==="
echo ""

# ─────────────────────────────────────────────────────────────
# Test 1 — POS-existing-whitelist: .baton/issue.md big Edit → PASS
# ─────────────────────────────────────────────────────────────
echo "Test 1: POS-existing-whitelist (.baton/issue.md, 100-line new_string) → PASS"
BIG=$(python3 -c "print('\n'.join(['x']*100))")
RESULT=$(run_guard_json "$PROJECT" "" "
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': '.baton/issue.md',
        'old_string': '',
        'new_string': '''$(echo "$BIG" | python3 -c 'import sys; print(sys.stdin.read())')'''
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" = "0" ]; then
  pass "Test 1 (.baton/issue.md big diff → exit 0)"
else
  fail "Test 1 got exit $CODE (expected 0)"
  echo "    out: $(extract_out "$RESULT" | head -3)"
fi

# ─────────────────────────────────────────────────────────────
# Test 2 — POS-subagent: src/foo.ts with subagent active → PASS
# ─────────────────────────────────────────────────────────────
echo "Test 2: POS-subagent (src/foo.ts with .agent-stack) → PASS"
RESULT=$(run_guard_json "$PROJECT" "subagent" "
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'src/foo.ts',
        'old_string': 'a',
        'new_string': 'b'
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" = "0" ]; then
  pass "Test 2 (src/foo.ts with subagent → exit 0)"
else
  fail "Test 2 got exit $CODE (expected 0)"
fi

# ─────────────────────────────────────────────────────────────
# Test 3 — POS-root-config-small: tsconfig.json old=5 new=5 → PASS
# ─────────────────────────────────────────────────────────────
echo "Test 3: POS-root-config-small (tsconfig.json 5+5 line diff) → PASS"
RESULT=$(run_guard_json "$PROJECT" "" "
old = chr(10).join(['line %d' % i for i in range(5)])
new = chr(10).join(['LINE %d' % i for i in range(5)])
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'tsconfig.json',
        'old_string': old,
        'new_string': new
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" = "0" ]; then
  pass "Test 3 (tsconfig.json small diff → exit 0)"
else
  fail "Test 3 got exit $CODE (expected 0)"
  echo "    out: $(extract_out "$RESULT" | head -5)"
fi

# ─────────────────────────────────────────────────────────────
# Test 4 — POS-package-json-bump: 1-line diff → PASS
# ─────────────────────────────────────────────────────────────
echo "Test 4: POS-package-json-bump (package.json 1-line version bump) → PASS"
RESULT=$(run_guard_json "$PROJECT" "" "
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'package.json',
        'old_string': '\"version\": \"1.0.0\"',
        'new_string': '\"version\": \"1.0.1\"'
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" = "0" ]; then
  pass "Test 4 (package.json 1-line bump → exit 0)"
else
  fail "Test 4 got exit $CODE (expected 0)"
  echo "    out: $(extract_out "$RESULT" | head -5)"
fi

# ─────────────────────────────────────────────────────────────
# Test 5 — POS-readme-small: README.md ≤20-line diff → PASS
# ─────────────────────────────────────────────────────────────
echo "Test 5: POS-readme-small (README.md ~10+8 line diff) → PASS"
RESULT=$(run_guard_json "$PROJECT" "" "
old = chr(10).join(['before %d' % i for i in range(10)])
new = chr(10).join(['after %d' % i for i in range(8)])
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'README.md',
        'old_string': old,
        'new_string': new
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" = "0" ]; then
  pass "Test 5 (README.md small diff → exit 0)"
else
  fail "Test 5 got exit $CODE (expected 0)"
  echo "    out: $(extract_out "$RESULT" | head -5)"
fi

# ─────────────────────────────────────────────────────────────
# Test 6 — NEG-config-too-large: tsconfig.json 25-line diff → BLOCK
# ─────────────────────────────────────────────────────────────
echo "Test 6: NEG-config-too-large (tsconfig.json 25-line diff) → BLOCK config-lines-exceeded"
RESULT=$(run_guard_json "$PROJECT" "" "
old = chr(10).join(['o %d' % i for i in range(25)])
new = chr(10).join(['n %d' % i for i in range(25)])
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'tsconfig.json',
        'old_string': old,
        'new_string': new
    }
}
")
CODE=$(extract_code "$RESULT")
OUT=$(extract_out "$RESULT")
if [ "$CODE" != "0" ] && echo "$OUT" | grep -q "config-lines-exceeded"; then
  pass "Test 6 (tsconfig.json too-large → blocked with config-lines-exceeded)"
else
  fail "Test 6 got exit $CODE, out:"
  echo "$OUT" | head -8 | sed 's/^/      /'
fi

# ─────────────────────────────────────────────────────────────
# Test 7 — NEG-lockfile: package-lock.json 1-line → BLOCK lockfile-excluded
# ─────────────────────────────────────────────────────────────
echo "Test 7: NEG-lockfile (package-lock.json 1-line edit) → BLOCK lockfile-excluded"
RESULT=$(run_guard_json "$PROJECT" "" "
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'package-lock.json',
        'old_string': 'a',
        'new_string': 'b'
    }
}
")
CODE=$(extract_code "$RESULT")
OUT=$(extract_out "$RESULT")
if [ "$CODE" != "0" ] && echo "$OUT" | grep -q "lockfile-excluded"; then
  pass "Test 7 (package-lock.json → blocked with lockfile-excluded)"
else
  fail "Test 7 got exit $CODE, out:"
  echo "$OUT" | head -5 | sed 's/^/      /'
fi

# ─────────────────────────────────────────────────────────────
# Test 8 — NEG-pipeline-def: agents/worker.md → BLOCK pipeline-def-excluded
# ─────────────────────────────────────────────────────────────
echo "Test 8: NEG-pipeline-def (agents/worker.md) → BLOCK pipeline-def-excluded"
RESULT=$(run_guard_json "$PROJECT" "" "
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'agents/worker.md',
        'old_string': 'x',
        'new_string': 'y'
    }
}
")
CODE=$(extract_code "$RESULT")
OUT=$(extract_out "$RESULT")
if [ "$CODE" != "0" ] && echo "$OUT" | grep -q "pipeline-def-excluded"; then
  pass "Test 8 (agents/worker.md → blocked with pipeline-def-excluded)"
else
  fail "Test 8 got exit $CODE, out:"
  echo "$OUT" | head -5 | sed 's/^/      /'
fi

# ─────────────────────────────────────────────────────────────
# Test 9 — NEG-nested: config/app.json (5 lines) → BLOCK (not root-level)
# ─────────────────────────────────────────────────────────────
echo "Test 9: NEG-nested (config/app.json 5 lines) → BLOCK (not root)"
RESULT=$(run_guard_json "$PROJECT" "" "
old = chr(10).join(['x%d' % i for i in range(5)])
new = chr(10).join(['y%d' % i for i in range(5)])
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'config/app.json',
        'old_string': old,
        'new_string': new
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" != "0" ]; then
  pass "Test 9 (config/app.json → blocked, not whitelisted as root)"
else
  fail "Test 9 got exit $CODE (expected non-zero)"
fi

# ─────────────────────────────────────────────────────────────
# Test 10 — NEG-source-tree: src/foo.ts (no subagent) → BLOCK
# ─────────────────────────────────────────────────────────────
echo "Test 10: NEG-source-tree (src/foo.ts, no subagent) → BLOCK"
RESULT=$(run_guard_json "$PROJECT" "" "
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': 'src/foo.ts',
        'old_string': 'a',
        'new_string': 'b'
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" != "0" ]; then
  pass "Test 10 (src/foo.ts, no subagent → blocked)"
else
  fail "Test 10 got exit $CODE (expected non-zero)"
fi

# ─────────────────────────────────────────────────────────────
# Test 11 — POS-claude-plugin-manifest: .claude-plugin/plugin.json 1-line bump → PASS
# ─────────────────────────────────────────────────────────────
echo "Test 11: POS-claude-plugin-manifest (.claude-plugin/plugin.json 1-line version bump) → PASS"
RESULT=$(run_guard_json "$PROJECT" "" "
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': '.claude-plugin/plugin.json',
        'old_string': '\"version\": \"1.0.0\"',
        'new_string': '\"version\": \"1.0.1\"'
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" = "0" ]; then
  pass "Test 11 (.claude-plugin/plugin.json 1-line bump → exit 0)"
else
  fail "Test 11 got exit $CODE (expected 0)"
  echo "    out: $(extract_out "$RESULT" | head -5)"
fi

# ─────────────────────────────────────────────────────────────
# Test 12 — POS-claude-plugin-large: .claude-plugin/plugin.json 30-line diff → PASS (unlimited)
# ─────────────────────────────────────────────────────────────
echo "Test 12: POS-claude-plugin-large (.claude-plugin/plugin.json 15+15 line diff) → PASS (unlimited)"
RESULT=$(run_guard_json "$PROJECT" "" "
old = chr(10).join(['o %d' % i for i in range(15)])
new = chr(10).join(['n %d' % i for i in range(15)])
payload = {
    'tool_name': 'Edit',
    'tool_input': {
        'file_path': '.claude-plugin/plugin.json',
        'old_string': old,
        'new_string': new
    }
}
")
CODE=$(extract_code "$RESULT")
if [ "$CODE" = "0" ]; then
  pass "Test 12 (.claude-plugin/plugin.json 30-line diff → exit 0, unlimited)"
else
  fail "Test 12 got exit $CODE (expected 0 — should be unlimited)"
  echo "    out: $(extract_out "$RESULT" | head -5)"
fi

# ─────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo "────────────────────────────────"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
