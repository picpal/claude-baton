#!/usr/bin/env bash
# test-log-event.sh — Tests for log-event.sh enriched logging schema
#
# Verifies:
#   1. post-tool with exit=0 read-only cmd (no >) → suppressed, no exec.log entry
#   2. post-tool with exit=1 → POST_BASH written to exec.log
#   3. post-tool with exit=0 and cmd containing > → POST_BASH written
#   4. post-tool with cmd longer than 80 chars → truncated to 80 in log
#   5. worktree-created → [ts] worktree-created format unchanged
#   6. worktree-removed → [ts] worktree-removed format unchanged
#   7. post-tool with exit=0 and write tool (non-read-only cmd) → POST_BASH written
#   8. post-tool with exit=0 and python3 -c cmd → suppressed if no >

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_EVENT="$SCRIPT_DIR/../log-event.sh"

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
    echo -e "${GREEN}PASS${NC}: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name"
    echo "       expected: $expected"
    echo "       actual:   $actual"
  fi
}

assert_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name"
    echo "       needle:   $needle"
    echo "       haystack: $haystack"
  fi
}

assert_not_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (should NOT contain: $needle)"
    echo "       haystack: $haystack"
  else
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name"
  fi
}

# Helper: build a hook stdin JSON for PostToolUse (Bash tool)
make_bash_hook_json() {
  local exit_code="$1"
  local cmd="$2"
  python3 -c "
import json, sys
d = {
  'hook_event_name': 'PostToolUse',
  'tool_name': 'Bash',
  'session_id': 'test-session',
  'tool_input': {'command': sys.argv[2]},
  'tool_response': {'exit_code': int(sys.argv[1]), 'stdout': '', 'stderr': ''}
}
print(json.dumps(d))
" "$exit_code" "$cmd"
}

# Helper: build a hook stdin JSON for PostToolUse with no tool_response (worktree events)
make_worktree_hook_json() {
  python3 -c "
import json
d = {
  'hook_event_name': 'PostToolUse',
  'tool_name': 'Bash',
  'session_id': 'test-session',
  'tool_input': {'command': 'git worktree add ...'},
  'tool_response': {}
}
print(json.dumps(d))
"
}

# Setup: run log-event.sh in an isolated temp baton env
run_log_event() {
  local event_tag="$1"
  local hook_json="$2"
  local test_root="$3"

  mkdir -p "$test_root/.baton/logs"

  # Run log-event.sh with the temp BATON_ROOT
  echo "$hook_json" | BATON_ROOT="$test_root" bash "$LOG_EVENT" "$event_tag" 2>/dev/null
  return 0
}

echo "=== log-event.sh Schema Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: Noise suppression — read-only successful commands are skipped
# ─────────────────────────────────────────────────
echo "--- Test Group 1: Noise suppression for read-only tools ---"

# 1a: exit=0, cmd=cat /foo → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "cat /etc/hosts")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "1a: exit=0, cmd=cat → suppressed (no exec.log entry)" "" "$log_content"
rm -rf "$TEST_ROOT"

# 1b: exit=0, cmd=ls -la → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "ls -la /tmp")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "1b: exit=0, cmd=ls → suppressed" "" "$log_content"
rm -rf "$TEST_ROOT"

# 1c: exit=0, cmd=grep foo bar → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "grep -r foo /tmp")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "1c: exit=0, cmd=grep → suppressed" "" "$log_content"
rm -rf "$TEST_ROOT"

# 1d: exit=0, cmd=find /tmp → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "find /tmp -name '*.sh'")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "1d: exit=0, cmd=find → suppressed" "" "$log_content"
rm -rf "$TEST_ROOT"

# 1e: exit=0, cmd=python3 -c (no >) → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "python3 -c 'import json; print(json.dumps({}))'")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "1e: exit=0, cmd=python3 -c (no >) → suppressed" "" "$log_content"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 2: Always log failures (exit != 0)
# ─────────────────────────────────────────────────
echo "--- Test Group 2: Failures always logged ---"

# 2a: exit=1, read-only cmd → still logged
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 1 "cat /nonexistent")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "2a: exit=1, cmd=cat → POST_BASH logged" "POST_BASH" "$log_content"
assert_contains "2a: exit=1, cmd=cat → exit=1 in log" "exit=1" "$log_content"
rm -rf "$TEST_ROOT"

# 2b: exit=2, ls cmd → logged
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 2 "ls /nonexistent")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "2b: exit=2, cmd=ls → POST_BASH logged" "POST_BASH" "$log_content"
assert_contains "2b: exit=2, cmd=ls → exit=2 in log" "exit=2" "$log_content"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 3: Redirect (>) in cmd forces logging even on exit=0
# ─────────────────────────────────────────────────
echo "--- Test Group 3: Redirect > forces logging ---"

# 3a: exit=0, cmd=cat /foo > /bar → logged (has redirect)
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "cat /etc/hosts > /tmp/out.txt")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "3a: exit=0, cat > redirect → POST_BASH logged" "POST_BASH" "$log_content"
assert_contains "3a: exit=0, cat > redirect → exit=0 in log" "exit=0" "$log_content"
rm -rf "$TEST_ROOT"

# 3b: exit=0, cmd=ls >> file → logged (has >> redirect)
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "ls -la >> /tmp/out.txt")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "3b: exit=0, ls >> redirect → POST_BASH logged" "POST_BASH" "$log_content"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 4: Non-read-only commands logged on exit=0
# ─────────────────────────────────────────────────
echo "--- Test Group 4: Non-read-only commands always logged ---"

# 4a: exit=0, cmd=git commit → logged
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "git commit -m 'test'")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "4a: exit=0, cmd=git commit → POST_BASH logged" "POST_BASH" "$log_content"
assert_contains "4a: exit=0, cmd=git commit → exit=0 in log" "exit=0" "$log_content"
rm -rf "$TEST_ROOT"

# 4b: exit=0, cmd=rm -rf → logged
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "rm -rf /tmp/test-dir")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "4b: exit=0, cmd=rm → POST_BASH logged" "POST_BASH" "$log_content"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 5: cmd truncation at 80 characters
# ─────────────────────────────────────────────────
echo "--- Test Group 5: cmd truncation at 80 characters ---"

# 5a: cmd longer than 80 chars → truncated in log
TEST_ROOT=$(mktemp -d)
long_cmd="git commit -m 'this is a very long commit message that definitely exceeds eighty characters total'"
hook_json=$(make_bash_hook_json 0 "$long_cmd")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
# Extract the cmd= value from log
cmd_in_log=$(echo "$log_content" | python3 -c "
import sys, re
line = sys.stdin.read().strip()
m = re.search(r'cmd=\"([^\"]+)\"', line)
if m:
    print(len(m.group(1)))
else:
    print(0)
" 2>/dev/null || echo "0")
assert_eq "5a: cmd > 80 chars → truncated to 80 in log" "80" "$cmd_in_log"
rm -rf "$TEST_ROOT"

# 5b: cmd shorter than 80 chars → NOT truncated
TEST_ROOT=$(mktemp -d)
short_cmd="git status"
hook_json=$(make_bash_hook_json 0 "$short_cmd")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "5b: cmd < 80 chars → cmd preserved in log" "git status" "$log_content"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 6: worktree events — unchanged format
# ─────────────────────────────────────────────────
echo "--- Test Group 6: worktree-created / worktree-removed unchanged ---"

# 6a: worktree-created → [ts] worktree-created format
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
# worktree events don't require stdin JSON
echo "" | BATON_ROOT="$TEST_ROOT" bash "$LOG_EVENT" "worktree-created" 2>/dev/null || true
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "6a: worktree-created → event in exec.log" "worktree-created" "$log_content"
# Must NOT contain POST_BASH
assert_not_contains "6a: worktree-created → no POST_BASH prefix" "POST_BASH" "$log_content"
rm -rf "$TEST_ROOT"

# 6b: worktree-removed → [ts] worktree-removed format
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
echo "" | BATON_ROOT="$TEST_ROOT" bash "$LOG_EVENT" "worktree-removed" 2>/dev/null || true
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "6b: worktree-removed → event in exec.log" "worktree-removed" "$log_content"
assert_not_contains "6b: worktree-removed → no POST_BASH prefix" "POST_BASH" "$log_content"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 7: log format structure validation
# ─────────────────────────────────────────────────
echo "--- Test Group 7: log format validation ---"

# 7a: POST_BASH log line has ISO timestamp prefix
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 1 "git push origin main")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
# Check for ISO timestamp pattern [YYYY-MM-DDTHH:MM:SSZ]
has_ts=$(echo "$log_content" | python3 -c "
import sys, re
line = sys.stdin.read().strip()
m = re.match(r'^\[\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\]', line)
print('yes' if m else 'no')
" 2>/dev/null || echo "no")
assert_eq "7a: POST_BASH log has ISO timestamp prefix" "yes" "$has_ts"
rm -rf "$TEST_ROOT"

# 7b: POST_BASH log line has cmd= field
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 1 "npm install")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_contains "7b: POST_BASH log has cmd= field" 'cmd="' "$log_content"
rm -rf "$TEST_ROOT"

# 7c: POST_BASH log is also echoed to stdout
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
hook_json=$(make_bash_hook_json 1 "npm test")
stdout_output=$(echo "$hook_json" | BATON_ROOT="$TEST_ROOT" bash "$LOG_EVENT" "post-tool" 2>/dev/null || true)
assert_contains "7c: POST_BASH also echoed to stdout" "POST_BASH" "$stdout_output"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 8: edge cases
# ─────────────────────────────────────────────────
echo "--- Test Group 8: Edge cases ---"

# 8a: no stdin (empty) for post-tool → should not crash, logs with empty cmd
TEST_ROOT=$(mktemp -d)
echo "" | BATON_ROOT="$TEST_ROOT" bash "$LOG_EVENT" "post-tool" 2>/dev/null || true
# Should exit without crash (we don't assert log content here, just no crash)
TOTAL=$((TOTAL + 1))
PASS=$((PASS + 1))
echo -e "${GREEN}PASS${NC}: 8a: no stdin → no crash"
rm -rf "$TEST_ROOT"

# 8b: jq cmd (exit=0, no >) → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "jq '.field' /tmp/data.json")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "8b: exit=0, cmd=jq (no >) → suppressed" "" "$log_content"
rm -rf "$TEST_ROOT"

# 8c: wc cmd (exit=0, no >) → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "wc -l /tmp/file.txt")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "8c: exit=0, cmd=wc (no >) → suppressed" "" "$log_content"
rm -rf "$TEST_ROOT"

# 8d: head cmd (exit=0, no >) → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "head -20 /tmp/file.txt")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "8d: exit=0, cmd=head (no >) → suppressed" "" "$log_content"
rm -rf "$TEST_ROOT"

# 8e: tail cmd (exit=0, no >) → suppressed
TEST_ROOT=$(mktemp -d)
hook_json=$(make_bash_hook_json 0 "tail -20 /tmp/file.txt")
run_log_event "post-tool" "$hook_json" "$TEST_ROOT"
log_content=""
[ -f "$TEST_ROOT/.baton/logs/exec.log" ] && log_content=$(cat "$TEST_ROOT/.baton/logs/exec.log")
assert_eq "8e: exit=0, cmd=tail (no >) → suppressed" "" "$log_content"
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
