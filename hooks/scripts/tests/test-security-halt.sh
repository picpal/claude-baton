#!/usr/bin/env bash
# test-security-halt.sh — Tests for security-halt.sh state.json integration (T4)
#
# Verifies that security-halt.sh:
#   1. Sets state.json securityHalt=true
#   2. Writes an exec.log entry
#   3. Captures severity/finding/timestamp into securityHaltContext.*
#   4. After running, regress_to_phase is blocked (SC-REGRESS-03, exit 3)
#   5. After clearing securityHalt manually, regress_to_phase works again
#   6. Does NOT call regress_to_phase itself (currentPhase unchanged)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SECURITY_HALT_SCRIPT="$SCRIPT_DIR/../security-halt.sh"
REGRESS_SCRIPT="$SCRIPT_DIR/../regress-to-phase.sh"
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

assert_contains() {
  local test_name="$1"
  local needle="$2"
  local haystack="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -q -- "$needle"; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name (contains \"$needle\")"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (missing \"$needle\")"
    echo "       haystack: $haystack"
  fi
}

# Helper: read a field from state.json
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

# Helper: seed a minimal valid Tier 2 state.json at review phase
# (matches test-regress-to-phase write_test_state pattern)
write_test_state() {
  local dir="$1"
  local tier="${2:-2}"
  local current_phase="${3:-review}"
  python3 - <<PYEOF
import json
state = {
    'version': 3,
    'currentTier': $tier,
    'currentPhase': '$current_phase',
    'phaseFlags': {
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': True,
        'qaIntegrationPassed': True,
        'reviewCompleted': False,
        'issueRegistered': True
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker': {'expected': 3, 'completed': []},
    'workerTracker': {'expected': 2, 'doneCount': 2},
    'qaRetryCount': {},
    'reworkStatus': {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [],
    'artifactStale': {},
    'lastCommitAttemptCount': 0,
    'securityHalt': False,
    'lastSafeTag': None,
    'issueNumber': 42,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': '2026-04-05T00:00:00Z'
}
with open('$dir/.baton/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
PYEOF
}

# Helper: run security-halt.sh in an isolated BATON_ROOT
run_security_halt() {
  local baton_root="$1"
  shift
  local exit_code=0
  (
    cd "$baton_root"
    BATON_ROOT="$baton_root" bash "$SECURITY_HALT_SCRIPT" "$@"
  ) > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

echo "=== security-halt.sh Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test 1: securityHalt=true written to state.json
# ─────────────────────────────────────────────────
echo "--- Test 1: securityHalt=true in state.json ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"

run_security_halt "$TEST_ROOT"

actual=$(read_state_field "$TEST_ROOT" "securityHalt")
assert_eq "1: state.json securityHalt=true after halt" "true" "$actual"
rm -rf "$TEST_ROOT"

# ─────────────────────────────────────────────────
# Test 2: exec.log entry is written
# ─────────────────────────────────────────────────
echo ""
echo "--- Test 2: exec.log entry ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"

run_security_halt "$TEST_ROOT"

if [ -f "$TEST_ROOT/.baton/logs/exec.log" ]; then
  log_contents=$(cat "$TEST_ROOT/.baton/logs/exec.log")
  assert_contains "2a: exec.log contains SECURITY_HALT" "SECURITY_HALT" "$log_contents"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 2a: exec.log not created"
fi
rm -rf "$TEST_ROOT"

# ─────────────────────────────────────────────────
# Test 3: securityHaltContext written when args provided
# ─────────────────────────────────────────────────
echo ""
echo "--- Test 3: securityHaltContext capture ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"

run_security_halt "$TEST_ROOT" "CRITICAL" "SQL injection in login" "security-guardian"

actual=$(read_state_field "$TEST_ROOT" "securityHaltContext.severity")
assert_eq "3a: securityHaltContext.severity=CRITICAL" "CRITICAL" "$actual"

actual=$(read_state_field "$TEST_ROOT" "securityHaltContext.finding")
assert_eq "3b: securityHaltContext.finding captured" "SQL injection in login" "$actual"

actual=$(read_state_field "$TEST_ROOT" "securityHaltContext.timestamp")
if [ -n "$actual" ] && [ "$actual" != "null" ]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 3c: securityHaltContext.timestamp is set ($actual)"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 3c: securityHaltContext.timestamp is null/empty"
fi
rm -rf "$TEST_ROOT"

# ─────────────────────────────────────────────────
# Test 4: After security-halt, regress_to_phase fails with exit 3
# ─────────────────────────────────────────────────
echo ""
echo "--- Test 4: regress_to_phase blocked by SC-REGRESS-03 ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"

run_security_halt "$TEST_ROOT" "HIGH" "hardcoded secret" "security-guardian"

exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'manual recovery'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "4a: regress_to_phase after security-halt -> exit 3" "3" "$exit_code"

# currentPhase should be unchanged: security-halt must NOT call regress itself
actual=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "4b: currentPhase unchanged (security-halt does not regress)" "review" "$actual"
rm -rf "$TEST_ROOT"

# ─────────────────────────────────────────────────
# Test 5: After clearing securityHalt manually, regress_to_phase works
# ─────────────────────────────────────────────────
echo ""
echo "--- Test 5: Clearing securityHalt unblocks regression ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"

run_security_halt "$TEST_ROOT" "CRITICAL" "path traversal" "security-guardian"

# Manually clear securityHalt (simulates Main after git revert + user confirm)
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$STATE_MANAGER'
  state_write 'securityHalt' 'false'
" > /dev/null 2>&1

# Depth from review(7) to planning(3) is 4, requires --force
exit_code=0
BATON_ROOT="$TEST_ROOT" bash -c "
  source '$REGRESS_SCRIPT'
  regress_to_phase 'planning' 'post-rollback' '--force'
" > /dev/null 2>&1 || exit_code=$?
assert_eq "5a: regress after clearing securityHalt succeeds (exit 0)" "0" "$exit_code"

actual=$(read_state_field "$TEST_ROOT" "currentPhase")
assert_eq "5b: currentPhase=planning after regress" "planning" "$actual"
rm -rf "$TEST_ROOT"

# ─────────────────────────────────────────────────
# Test 6: security-report.md placeholder still produced
# ─────────────────────────────────────────────────
echo ""
echo "--- Test 6: security-report.md created ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
write_test_state "$TEST_ROOT" 2 "review"

run_security_halt "$TEST_ROOT"

if [ -f "$TEST_ROOT/.baton/reports/security-report.md" ]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 6: security-report.md placeholder written"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 6: security-report.md missing"
fi
rm -rf "$TEST_ROOT"

# ─────────────────────────────────────────────────
# Test 7: Runs cleanly when state.json is absent (no crash)
# ─────────────────────────────────────────────────
echo ""
echo "--- Test 7: Defensive behavior with missing state.json ---"

TEST_ROOT=$(mktemp -d)
mkdir -p "$TEST_ROOT/.baton/logs"
# Intentionally no state.json — state_write should auto-init via state_manager

exit_code=0
run_security_halt "$TEST_ROOT" || exit_code=$?
assert_eq "7a: security-halt exits 0 when state.json missing (auto-init)" "0" "$exit_code"

if [ -f "$TEST_ROOT/.baton/state.json" ]; then
  actual=$(read_state_field "$TEST_ROOT" "securityHalt")
  assert_eq "7b: state.json auto-created with securityHalt=true" "true" "$actual"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 7b: state.json was not auto-created"
fi
rm -rf "$TEST_ROOT"

# ─────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────
echo ""
echo "=== Results ==="
echo "Total:  $TOTAL"
echo -e "Passed: ${GREEN}$PASS${NC}"
if [ "$FAIL" -gt 0 ]; then
  echo -e "Failed: ${RED}$FAIL${NC}"
  exit 1
fi
echo -e "Failed: $FAIL"
exit 0
