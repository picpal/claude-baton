#!/usr/bin/env bash
# test-stack-ttl.sh — Tests for prune_stale_stack_entries in state-manager.sh
#
# Verifies:
#   1. Empty AGENT_NAME entries removed regardless of age
#   2. Old TTL entries removed (STACK_TTL_SECONDS=1 short TTL test)
#   3. Recent valid entries kept
#   4. Mixed: 5 entries (2 zombies, 3 valid) → 2 removed, 3 kept
#   5. Missing file → returns 0, no error
#   6. STACK_TTL_SECONDS env var respected
#   7. Atomic write — no tmp file left behind after successful prune

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATE_MANAGER="$SCRIPT_DIR/../state-manager.sh"

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
    echo -e "${RED}FAIL${NC}: $test_name (expected='$expected', actual='$actual')"
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

# Helper: fresh ISO8601 UTC timestamp (now)
now_ts() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

# Helper: stale ISO8601 UTC timestamp (2 hours ago + some)
stale_ts() {
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(hours=3)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

# Helper: slightly old timestamp (1+ seconds ago) — used for TTL=1 tests
old_ts_1s() {
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=5)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

# Helper: 90s-old timestamp — older than the 60s floor, used for TTL floor tests
old_ts_90s() {
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=90)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

echo "=== prune_stale_stack_entries Tests ==="
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 1: Missing file → returns 0, no error
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 1: Missing file ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
NONEXISTENT="$TEST_ROOT/.baton/logs/.agent-stack"

result=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  prune_stale_stack_entries '$NONEXISTENT'
" 2>/dev/null)

assert_eq "1a: missing file → returns 0" "0" "$result"

# Ensure no file was created
if [ -f "$NONEXISTENT" ]; then
  assert_eq "1b: missing file → no file created" "false" "true"
else
  assert_eq "1b: missing file → no file created" "false" "false"
fi

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 2: Empty AGENT_NAME entries removed regardless of age
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 2: Empty AGENT_NAME entries removed ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

FRESH=$(now_ts)
# Entry with empty AGENT_NAME (legacy zombie shape)
printf '%s|\n' "$FRESH" >> "$STACK_FILE"
# Entry with whitespace-only AGENT_NAME
printf '%s|   \n' "$FRESH" >> "$STACK_FILE"

result=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "2a: 2 empty-name entries → returns 2" "2" "$result"

# File should now be empty (0 lines)
if [ -f "$STACK_FILE" ]; then
  remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
else
  remaining="0"
fi
assert_eq "2b: file empty after removing 2 empty-name entries" "0" "$remaining"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 3: Recent valid entries kept
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 3: Recent valid entries kept ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

FRESH=$(now_ts)
printf '%s|claude-baton:worker-agent\n' "$FRESH" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$FRESH" >> "$STACK_FILE"

result=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "3a: 2 fresh valid entries → returns 0" "0" "$result"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "3b: file still has 2 lines after no-op prune" "2" "$remaining"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 4: Old TTL entries removed (STACK_TTL_SECONDS=70, entries 90s old)
# Note: minimum floor is 60s; TTL=70 is above floor so actual TTL=70 applies.
# Entries 90s old exceed 70s TTL and must be removed.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 4: Old TTL entries removed with TTL=70s (above 60s floor) ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

OLD=$(old_ts_90s)
printf '%s|claude-baton:worker-agent\n' "$OLD" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$OLD" >> "$STACK_FILE"

result=$(BATON_ROOT="$TEST_ROOT" STACK_TTL_SECONDS=70 bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  STACK_TTL_SECONDS=70 prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "4a: 2 stale TTL entries (TTL=70s, age=90s) → returns 2" "2" "$result"

if [ -f "$STACK_FILE" ]; then
  remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
else
  remaining="0"
fi
assert_eq "4b: file empty after removing 2 stale TTL entries" "0" "$remaining"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 5: Mixed — 2 zombies + 3 valid → 2 removed, 3 kept
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 5: Mixed entries (2 zombies, 3 valid) ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

FRESH=$(now_ts)
STALE=$(stale_ts)

# 2 zombie entries (empty name)
printf '%s|\n' "$FRESH" >> "$STACK_FILE"
printf '%s|\n' "$STALE" >> "$STACK_FILE"
# 3 valid fresh entries
printf '%s|claude-baton:worker-agent\n' "$FRESH" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$FRESH" >> "$STACK_FILE"
printf '%s|claude-baton:review-agent\n' "$FRESH" >> "$STACK_FILE"

result=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "5a: mixed 5 entries (2 zombies) → returns 2" "2" "$result"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "5b: 3 valid entries remain after pruning 2 zombies" "3" "$remaining"

# Verify the valid entries are still present
has_worker=$(grep -c "worker-agent" "$STACK_FILE" 2>/dev/null || echo "0")
has_qa=$(grep -c "qa-unit" "$STACK_FILE" 2>/dev/null || echo "0")
has_review=$(grep -c "review-agent" "$STACK_FILE" 2>/dev/null || echo "0")
assert_eq "5c: worker-agent entry preserved" "1" "$has_worker"
assert_eq "5d: qa-unit entry preserved" "1" "$has_qa"
assert_eq "5e: review-agent entry preserved" "1" "$has_review"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 6: STACK_TTL_SECONDS env var respected
# Note: minimum floor is 60s. We use a 90s-old entry (above floor) and
# TTL=70s (above floor) to verify env var removal; also verify default 7200s keeps it.
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 6: STACK_TTL_SECONDS env var respected ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

FRESH=$(now_ts)
# Use an entry that is 90s old — should survive default TTL=7200 but not TTL=70
OLD=$(old_ts_90s)
printf '%s|claude-baton:worker-agent\n' "$OLD" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$FRESH" >> "$STACK_FILE"

# With default TTL (7200s) — both should be kept (90s old < 7200s)
result_default=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "6a: default TTL=7200 — 90s-old entry kept (returns 0)" "0" "$result_default"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "6b: default TTL — both entries still in file" "2" "$remaining"

# Now with TTL=70 (above 60s floor) — the 90s-old entry should be pruned, fresh stays
result_short=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  STACK_TTL_SECONDS=70 prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "6c: TTL=70 — 90s-old entry removed (returns 1)" "1" "$result_short"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "6d: TTL=70 — only 1 fresh entry remains" "1" "$remaining"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 7: Atomic write — no tmp file left behind
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 7: Atomic write — tmp file cleaned up ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"
LOG_DIR="$TEST_ROOT/.baton/logs"

FRESH=$(now_ts)
# 1 zombie + 1 valid
printf '%s|\n' "$FRESH" >> "$STACK_FILE"
printf '%s|claude-baton:worker-agent\n' "$FRESH" >> "$STACK_FILE"

BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null

# No tmp files should remain in the logs dir
tmp_count=$(find "$LOG_DIR" -name "tmp*" -o -name "*.tmp.*" 2>/dev/null | wc -l | tr -d ' ')
assert_eq "7a: no tmp files left in logs dir after prune" "0" "$tmp_count"

# Stack file still exists and has 1 valid entry
remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "7b: valid entry preserved after atomic write" "1" "$remaining"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Test Group 8: STACK_TTL_SECONDS minimum floor — STACK_TTL_SECONDS=0 uses 60s floor
#
# Security fix: STACK_TTL_SECONDS=0 must NOT instantly clear all entries.
#   - A 30s-old entry should survive STACK_TTL_SECONDS=0 (floor=60s applies)
#   - STACK_TTL_SECONDS=10 still uses 60s floor → 30s-old entry survives
#   - STACK_TTL_SECONDS=120 uses 120s → 90s-old entry survives, 150s-old removed
# ─────────────────────────────────────────────────────────────────────────────
echo "--- Test Group 8: STACK_TTL_SECONDS minimum floor (60s) ---"

# Helper: entry N seconds old
ts_ago() {
  local secs="$1"
  python3 -c "
from datetime import datetime, timezone, timedelta
t = datetime.now(timezone.utc) - timedelta(seconds=$secs)
print(t.strftime('%Y-%m-%dT%H:%M:%SZ'))
"
}

# ── 8a: STACK_TTL_SECONDS=0 → 30s-old entry kept (floor 60s enforced) ────────
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

TS_30S=$(ts_ago 30)
printf '%s|claude-baton:worker-agent\n' "$TS_30S" >> "$STACK_FILE"

result=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  STACK_TTL_SECONDS=0 prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "8a: STACK_TTL_SECONDS=0, 30s-old entry kept (floor=60s) → returns 0" "0" "$result"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "8b: STACK_TTL_SECONDS=0 → 30s-old entry still in file" "1" "$remaining"

rm -rf "$TEST_ROOT"

# ── 8c: STACK_TTL_SECONDS=10 → 30s-old entry still kept (floor 60s) ─────────
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

TS_30S=$(ts_ago 30)
printf '%s|claude-baton:qa-unit\n' "$TS_30S" >> "$STACK_FILE"

result=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  STACK_TTL_SECONDS=10 prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "8c: STACK_TTL_SECONDS=10, 30s-old entry kept (floor=60s) → returns 0" "0" "$result"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "8d: STACK_TTL_SECONDS=10 → 30s-old entry still in file" "1" "$remaining"

rm -rf "$TEST_ROOT"

# ── 8e: STACK_TTL_SECONDS=120 → 90s-old kept, 150s-old removed ──────────────
TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
STACK_FILE="$TEST_ROOT/.baton/logs/.agent-stack"

TS_90S=$(ts_ago 90)
TS_150S=$(ts_ago 150)
printf '%s|claude-baton:worker-agent\n' "$TS_90S" >> "$STACK_FILE"
printf '%s|claude-baton:qa-unit\n' "$TS_150S" >> "$STACK_FILE"

result=$(BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER' 2>/dev/null
  STACK_TTL_SECONDS=120 prune_stale_stack_entries '$STACK_FILE'
" 2>/dev/null)

assert_eq "8e: STACK_TTL_SECONDS=120, 150s-old removed → returns 1" "1" "$result"

remaining=$(wc -l < "$STACK_FILE" | tr -d ' ')
assert_eq "8f: STACK_TTL_SECONDS=120 → only 90s-old entry remains" "1" "$remaining"

has_worker=$(grep -c "worker-agent" "$STACK_FILE" 2>/dev/null || echo "0")
assert_eq "8g: STACK_TTL_SECONDS=120 → 90s-old worker-agent entry preserved" "1" "$has_worker"

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
