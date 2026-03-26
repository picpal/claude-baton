#!/usr/bin/env bash
# test-verify-before-commit.sh — Tests for verify-before-commit.sh
#
# Verifies:
#   1. tier=null, phase=idle → commit ALLOWED (init-phase exemption)
#   2. tier=null, phase=null → commit ALLOWED (init-phase exemption)
#   3. tier=1, qaUnitPassed=false → commit BLOCKED
#   4. tier=2, reviewCompleted=false → commit BLOCKED
#   5. tier=1, qaUnitPassed=true → commit ALLOWED
#   6. reworkStatus.active=true → commit ALLOWED
#   7. No .baton/ directory → commit ALLOWED (pre-init)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/../verify-before-commit.sh"

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

# Helper: build JSON payload for a git commit command
make_commit_json() {
  python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'PreToolUse',
    'tool_name': 'Bash',
    'session_id': 'test-session',
    'tool_input': {'command': 'git commit -m \"test\"'}
}, ensure_ascii=False))
"
}

# Helper: write a state.json with given fields
write_state() {
  local dir="$1"
  local tier="$2"       # "null" or number as string
  local phase="$3"      # "idle", "null", "analysis", etc.
  local qa_unit="$4"    # "true" or "false"
  local review="$5"     # "true" or "false"
  local rework="${6:-false}"  # "true" or "false"

  python3 -c "
import json, sys

qa_unit_val = ('$qa_unit' == 'true')
review_val = ('$review' == 'true')
rework_val = ('$rework' == 'true')
tier_val = None if '$tier' == 'null' else int('$tier')
phase_val = None if '$phase' == 'null' else '$phase'

state = {
    'version': 1,
    'currentTier': tier_val,
    'currentPhase': phase_val,
    'phaseFlags': {
        'analysisCompleted': False,
        'interviewCompleted': False,
        'planningCompleted': False,
        'taskMgrCompleted': False,
        'workerCompleted': False,
        'qaUnitPassed': qa_unit_val,
        'qaIntegrationPassed': False,
        'reviewCompleted': review_val
    },
    'planningTracker': {'expected': 0, 'completed': []},
    'reviewTracker': {'expected': 0, 'completed': []},
    'workerTracker': {'expected': 0, 'doneCount': 0},
    'qaRetryCount': {},
    'reworkStatus': {'active': rework_val, 'attemptCount': 0},
    'securityHalt': False,
    'lastSafeTag': None,
    'timestamp': ''
}

with open('$dir/state.json', 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
"
}

# Run the hook with a git commit command against a given BATON_ROOT
# Returns exit code of the hook
run_hook() {
  local baton_root="$1"
  local exit_code=0
  local json
  json=$(make_commit_json)
  echo "$json" | BATON_ROOT="$baton_root" bash "$HOOK_SCRIPT" > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

echo "=== verify-before-commit.sh Tests ==="
echo ""

# ─────────────────────────────────────────────────
# Test Group 1: Init-phase exemption (tier=null)
# ─────────────────────────────────────────────────
echo "--- Test Group 1: Init-phase exemption (tier=null) → ALLOWED ---"

# 1a: tier=null, phase=idle (standard baton:init state)
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "null" "idle" "false" "false"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_allowed "1a: tier=null, phase=idle → commit ALLOWED (init state)" "$exit_code"
rm -rf "$TEST_ROOT"

# 1b: tier=null, phase=null (edge case: null phase)
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "null" "null" "false" "false"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_allowed "1b: tier=null, phase=null → commit ALLOWED (null phase)" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 2: Active pipeline — commit BLOCKED
# ─────────────────────────────────────────────────
echo "--- Test Group 2: Active pipeline → commit BLOCKED ---"

# 2a: tier=1, qaUnitPassed=false → BLOCKED
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "1" "analysis" "false" "false"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_blocked "2a: tier=1, qaUnitPassed=false → commit BLOCKED" "$exit_code"
rm -rf "$TEST_ROOT"

# 2b: tier=2, reviewCompleted=false → BLOCKED
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "2" "review" "true" "false"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_blocked "2b: tier=2, reviewCompleted=false → commit BLOCKED" "$exit_code"
rm -rf "$TEST_ROOT"

# 2c: tier=3, reviewCompleted=false → BLOCKED
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "3" "review" "true" "false"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_blocked "2c: tier=3, reviewCompleted=false → commit BLOCKED" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 3: Active pipeline — commit ALLOWED
# ─────────────────────────────────────────────────
echo "--- Test Group 3: Active pipeline — requirements met → ALLOWED ---"

# 3a: tier=1, qaUnitPassed=true → ALLOWED
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "1" "worker" "true" "false"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_allowed "3a: tier=1, qaUnitPassed=true → commit ALLOWED" "$exit_code"
rm -rf "$TEST_ROOT"

# 3b: tier=2, reviewCompleted=true → ALLOWED
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "2" "review" "true" "true"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_allowed "3b: tier=2, reviewCompleted=true → commit ALLOWED" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 4: Rework state → commit ALLOWED
# ─────────────────────────────────────────────────
echo "--- Test Group 4: reworkStatus.active=true → ALLOWED ---"

# 4a: tier=1, qaUnitPassed=false, but rework active → ALLOWED
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "1" "worker" "false" "false" "true"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_allowed "4a: tier=1, qaUnitPassed=false, rework.active=true → commit ALLOWED" "$exit_code"
rm -rf "$TEST_ROOT"

# 4b: tier=2, reviewCompleted=false, but rework active → ALLOWED
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "2" "worker" "false" "false" "true"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_allowed "4b: tier=2, reviewCompleted=false, rework.active=true → commit ALLOWED" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 5: Pre-init (no .baton dir) → ALLOWED
# ─────────────────────────────────────────────────
echo "--- Test Group 5: No .baton directory → ALLOWED (pre-init) ---"

# 5a: No .baton dir at all.
#     Note: ensure_baton_dirs() runs at hook startup and creates .baton/logs,
#     then state_init() creates state.json with tier=null/phase=idle.
#     The init-phase exemption covers this case — tier=null + phase=idle → ALLOWED.
TEST_ROOT=$(mktemp -d)
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_allowed "5a: no .baton dir → tier=null/phase=idle auto-created → commit ALLOWED" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Security: idle phase must NOT bypass active pipeline
# ─────────────────────────────────────────────────
echo "--- Test Group 6: Security — idle phase with active tier must still block ---"

# 6a: tier is set (e.g., 1) but phase tampered to "idle" → BLOCKED
#     (tier != null/0 takes precedence — exemption is only for null tier)
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "1" "idle" "false" "false"
exit_code=0
run_hook "$TEST_ROOT" || exit_code=$?
assert_blocked "6a: tier=1, phase=idle (tampered), qaUnitPassed=false → still BLOCKED" "$exit_code"
rm -rf "$TEST_ROOT"

echo ""

# ─────────────────────────────────────────────────
# Test Group 7: Subagent active → commit ALLOWED (Worker checkpoint)
# ─────────────────────────────────────────────────
echo "--- Test Group 7: Subagent active → ALLOWED (Worker checkpoint) ---"

# Helper: run hook with an agent-stack file present
run_hook_with_agent() {
  local baton_root="$1"
  local agent_name="${2:-worker-1}"
  local baton_dir="$baton_root/.baton"
  local agent_stack_file="$baton_dir/logs/.agent-stack"
  mkdir -p "$baton_dir/logs"
  echo "2024-01-01T00:00:00|$agent_name" > "$agent_stack_file"
  local exit_code=0
  local json
  json=$(make_commit_json)
  echo "$json" | BATON_ROOT="$baton_root" bash "$HOOK_SCRIPT" > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

# Helper: run hook with NO agent-stack file (ensure it's absent)
run_hook_no_agent() {
  local baton_root="$1"
  local baton_dir="$baton_root/.baton"
  rm -f "$baton_dir/logs/.agent-stack"
  local exit_code=0
  local json
  json=$(make_commit_json)
  echo "$json" | BATON_ROOT="$baton_root" bash "$HOOK_SCRIPT" > /dev/null 2>&1 || exit_code=$?
  return $exit_code
}

# 7a: Subagent active + Tier 2 + reviewCompleted=false → ALLOWED (Worker checkpoint)
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "2" "worker" "true" "false"
exit_code=0
run_hook_with_agent "$TEST_ROOT" "worker-1" || exit_code=$?
assert_allowed "7a: subagent active + tier=2 + reviewCompleted=false → ALLOWED (Worker checkpoint)" "$exit_code"
rm -rf "$TEST_ROOT"

# 7b: Subagent active + Tier 1 + qaUnitPassed=false → ALLOWED (Worker checkpoint)
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "1" "worker" "false" "false"
exit_code=0
run_hook_with_agent "$TEST_ROOT" "worker-2" || exit_code=$?
assert_allowed "7b: subagent active + tier=1 + qaUnitPassed=false → ALLOWED (Worker checkpoint)" "$exit_code"
rm -rf "$TEST_ROOT"

# 7c: No subagent + Tier 2 + reviewCompleted=false → BLOCKED (Main can't bypass)
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "2" "worker" "true" "false"
exit_code=0
run_hook_no_agent "$TEST_ROOT" || exit_code=$?
assert_blocked "7c: no subagent + tier=2 + reviewCompleted=false → BLOCKED (Main can't bypass)" "$exit_code"
rm -rf "$TEST_ROOT"

# 7d: No subagent + Tier 1 + qaUnitPassed=false → BLOCKED (Main can't bypass)
TEST_ROOT=$(mktemp -d)
TEST_BATON="$TEST_ROOT/.baton"
mkdir -p "$TEST_BATON/logs"
write_state "$TEST_BATON" "1" "worker" "false" "false"
exit_code=0
run_hook_no_agent "$TEST_ROOT" || exit_code=$?
assert_blocked "7d: no subagent + tier=1 + qaUnitPassed=false → BLOCKED (Main can't bypass)" "$exit_code"
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
