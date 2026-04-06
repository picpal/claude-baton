#!/usr/bin/env bash
# test-schema-v3.sh — Tests for state-manager.sh Schema v3 Migration
#
# Verifies:
#   1. state_init() creates state.json with version=3 and all v3 fields
#   2. state_migrate() on a v2 state.json adds missing v3 fields without losing existing data
#   3. state_array_clear() correctly empties an array field

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
    echo -e "${RED}FAIL${NC}: $test_name (expected=$expected, actual=$actual)"
  fi
}

# Helper: read a field from a state.json in given directory
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

# Helper: write a minimal v2 state.json
write_v2_state() {
  local dir="$1"
  mkdir -p "$dir/.baton"
  python3 -c "
import json
state = {
    'version': 2,
    'currentTier': 2,
    'currentPhase': 'worker',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': False,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': { 'expected': 1, 'completed': ['Planning Agent'] },
    'reviewTracker': { 'expected': 3, 'completed': [] },
    'workerTracker': { 'expected': 2, 'doneCount': 1 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 1 },
    'securityHalt': False,
    'lastSafeTag': 'v1.0.0',
    'issueNumber': 42,
    'issueUrl': 'https://github.com/example/repo/issues/42',
    'issueLabels': ['bug'],
    'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
with open('$dir/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
}

echo "=== Schema v3 Migration Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: state_init() creates v3 schema with all new fields
# ─────────────────────────────────────────────────
echo "--- Test Group 1: state_init() creates v3 schema ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

# Run state_init via sourcing state-manager.sh with overridden STATE_FILE
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_init
" 2>/dev/null

# 1a: version should be 3
actual=$(read_state_field "$TEST_ROOT" "version")
assert_eq "1a: state_init() sets version=3" "3" "$actual"

# 1b: regressionHistory should be an empty array
actual=$(read_state_field "$TEST_ROOT" "regressionHistory")
assert_eq "1b: state_init() sets regressionHistory=[]" "[]" "$actual"

# 1c: artifactStale should be an empty object
actual=$(read_state_field "$TEST_ROOT" "artifactStale")
assert_eq "1c: state_init() sets artifactStale={}" "{}" "$actual"

# 1d: reworkStatus.hasWarnings should be false
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_eq "1d: state_init() sets reworkStatus.hasWarnings=false" "false" "$actual"

# 1e: reworkStatus.active should be false (existing field preserved)
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
assert_eq "1e: state_init() sets reworkStatus.active=false" "false" "$actual"

# 1f: reworkStatus.attemptCount should be 0
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.attemptCount")
assert_eq "1f: state_init() sets reworkStatus.attemptCount=0" "0" "$actual"

# 1g: lastCommitAttemptCount should be 0
actual=$(read_state_field "$TEST_ROOT" "lastCommitAttemptCount")
assert_eq "1g: state_init() sets lastCommitAttemptCount=0" "0" "$actual"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test Group 2: state_migrate() adds v3 fields to existing v2 state without data loss
# ─────────────────────────────────────────────────
echo "--- Test Group 2: state_migrate() upgrades v2 state to v3 ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_v2_state "$TEST_ROOT"

# Run state_migrate via sourcing state-manager.sh
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_migrate
" 2>/dev/null

# 2a: version should be bumped to 3
actual=$(read_state_field "$TEST_ROOT" "version")
assert_eq "2a: state_migrate() bumps version to 3" "3" "$actual"

# 2b: regressionHistory should be added as empty array
actual=$(read_state_field "$TEST_ROOT" "regressionHistory")
assert_eq "2b: state_migrate() adds regressionHistory=[]" "[]" "$actual"

# 2c: artifactStale should be added as empty object
actual=$(read_state_field "$TEST_ROOT" "artifactStale")
assert_eq "2c: state_migrate() adds artifactStale={}" "{}" "$actual"

# 2d: reworkStatus.hasWarnings should be added as false
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_eq "2d: state_migrate() adds reworkStatus.hasWarnings=false" "false" "$actual"

# 2e: lastCommitAttemptCount should be added as 0
actual=$(read_state_field "$TEST_ROOT" "lastCommitAttemptCount")
assert_eq "2e: state_migrate() adds lastCommitAttemptCount=0" "0" "$actual"

# 2f: existing reworkStatus.active should be preserved (not overwritten)
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.active")
assert_eq "2f: state_migrate() preserves existing reworkStatus.active=false" "false" "$actual"

# 2g: existing reworkStatus.attemptCount=1 should be preserved
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.attemptCount")
assert_eq "2g: state_migrate() preserves existing reworkStatus.attemptCount=1" "1" "$actual"

# 2h: existing currentTier=2 should be preserved
actual=$(read_state_field "$TEST_ROOT" "currentTier")
assert_eq "2h: state_migrate() preserves existing currentTier=2" "2" "$actual"

# 2i: existing issueNumber=42 should be preserved
actual=$(read_state_field "$TEST_ROOT" "issueNumber")
assert_eq "2i: state_migrate() preserves existing issueNumber=42" "42" "$actual"

# 2j: existing lastSafeTag should be preserved
actual=$(read_state_field "$TEST_ROOT" "lastSafeTag")
assert_eq "2j: state_migrate() preserves existing lastSafeTag=v1.0.0" "v1.0.0" "$actual"

# 2k: existing workerTracker.doneCount=1 should be preserved
actual=$(read_state_field "$TEST_ROOT" "workerTracker.doneCount")
assert_eq "2k: state_migrate() preserves existing workerTracker.doneCount=1" "1" "$actual"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test Group 3: state_array_clear() empties an array field
# ─────────────────────────────────────────────────
echo "--- Test Group 3: state_array_clear() empties an array field ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

# Initialize v3 state with a non-empty regressionHistory
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_init
  state_write 'regressionHistory' '[\"entry1\", \"entry2\"]'
" 2>/dev/null

# 3a: verify regressionHistory has entries before clearing
actual=$(read_state_field "$TEST_ROOT" "regressionHistory")
assert_eq "3a: regressionHistory has entries before clear" '["entry1", "entry2"]' "$actual"

# 3b: state_array_clear empties regressionHistory
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_array_clear 'regressionHistory'
" 2>/dev/null

actual=$(read_state_field "$TEST_ROOT" "regressionHistory")
assert_eq "3b: state_array_clear('regressionHistory') sets it to []" "[]" "$actual"

# 3c: state_array_clear works on reviewTracker.completed
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_write 'reviewTracker.completed' '[\"Security Guardian\", \"QA Inspector\"]'
  state_array_clear 'reviewTracker.completed'
" 2>/dev/null

actual=$(read_state_field "$TEST_ROOT" "reviewTracker.completed")
assert_eq "3c: state_array_clear('reviewTracker.completed') sets it to []" "[]" "$actual"

# 3d: state_array_clear on an already-empty array is a no-op
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_write 'regressionHistory' '[]'
  state_array_clear 'regressionHistory'
" 2>/dev/null

actual=$(read_state_field "$TEST_ROOT" "regressionHistory")
assert_eq "3d: state_array_clear on empty array remains []" "[]" "$actual"

rm -rf "$TEST_ROOT"
echo ""

# ─────────────────────────────────────────────────
# Test Group 4: state_migrate() is idempotent on v3 state
# ─────────────────────────────────────────────────
echo "--- Test Group 4: state_migrate() is idempotent on v3 state ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"

# Initialize to v3, then write some data
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_init
  state_write 'regressionHistory' '[\"phase:qa->worker\"]'
  state_write 'reworkStatus.hasWarnings' 'true'
  state_write 'lastCommitAttemptCount' '3'
" 2>/dev/null

# Run migrate again on already-v3 state
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_migrate
" 2>/dev/null

# 4a: version still 3
actual=$(read_state_field "$TEST_ROOT" "version")
assert_eq "4a: idempotent migrate keeps version=3" "3" "$actual"

# 4b: regressionHistory data preserved
actual=$(read_state_field "$TEST_ROOT" "regressionHistory")
assert_eq "4b: idempotent migrate preserves regressionHistory" '["phase:qa->worker"]' "$actual"

# 4c: reworkStatus.hasWarnings=true preserved
actual=$(read_state_field "$TEST_ROOT" "reworkStatus.hasWarnings")
assert_eq "4c: idempotent migrate preserves reworkStatus.hasWarnings=true" "true" "$actual"

# 4d: lastCommitAttemptCount=3 preserved
actual=$(read_state_field "$TEST_ROOT" "lastCommitAttemptCount")
assert_eq "4d: idempotent migrate preserves lastCommitAttemptCount=3" "3" "$actual"

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
