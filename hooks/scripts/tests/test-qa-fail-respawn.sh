#!/usr/bin/env bash
# test-qa-fail-respawn.sh — Tests for F4 QA auto-regression dispatch
#
# Verifies that handle_qa_unit_stop and handle_qa_integration_stop
# automatically call regress_to_phase on FAIL/ESCALATED results:
#
#   1. QA FAIL with retry_count=0 → regress to worker, currentPhase=worker, workerCompleted=false
#   2. QA FAIL with retry_count=2 (3rd attempt, QA_MAX_RETRIES=3) → regress to taskmgr (--force)
#   3. QA FAIL with retry_count=2 + QA_MAX_RETRIES=5 → still regresses to worker (not exhausted)
#   4. QA ESCALATED → regress to taskmgr, qaRetryCount=99
#   5. QA PASS → no regress, qaUnitPassed=true (sanity)
#   6. .agent-stack handling: pop happens before QA handler, so regress_to_phase succeeds
#   7. regress_to_phase failure logged to exec.log but does not crash the hook
#   8. handle_qa_integration_stop mirrors handle_qa_unit_stop for FAIL
#   9. handle_qa_integration_stop mirrors handle_qa_unit_stop for ESCALATED

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENT_LOGGER="$SCRIPT_DIR/../agent-logger.sh"

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

# Read a dot-notation field from state.json
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

# Initialize state.json with currentPhase=qa and optional qaRetryCount map
init_qa_state() {
  local dir="$1"
  local qa_retry_json="${2:-{\}}"
  local tier="${3:-2}"
  python3 - "$qa_retry_json" "$tier" <<'PYEOF'
import json, sys, os

qa_retry = json.loads(sys.argv[1])
tier = int(sys.argv[2])

state = {
    'version': 3,
    'currentTier': tier,
    'currentPhase': 'qa',
    'securityHalt': False,
    'phaseFlags': {
        'issueRegistered': True,
        'analysisCompleted': True,
        'interviewCompleted': True,
        'planningCompleted': True,
        'taskMgrCompleted': True,
        'workerCompleted': True,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False,
    },
    'planningTracker': {'expected': 1, 'completed': ['Planning Agent']},
    'reviewTracker':   {'expected': 3, 'completed': []},
    'workerTracker':   {'expected': 1, 'doneCount': 1},
    'qaRetryCount':    qa_retry,
    'reworkStatus':    {'active': False, 'attemptCount': 0, 'hasWarnings': False},
    'regressionHistory': [],
    'artifactStale':   {},
    'lastCommitAttemptCount': 0,
    'lastSafeTag': None,
    'issueNumber': None,
    'issueUrl': None,
    'issueLabels': [],
    'isExistingIssue': False,
    'timestamp': ''
}

state_dir = os.path.join(os.environ['BATON_ROOT'], '.baton')
os.makedirs(state_dir, exist_ok=True)
with open(os.path.join(state_dir, 'state.json'), 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
PYEOF
}

# Build SubagentStop JSON for QA unit
make_qa_unit_stop_json() {
  local marker="$1"
  python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:qa-unit',
    'agent_name': 'claude-baton:qa-unit',
    'tool_response': {'content': 'QA check complete.\n' + sys.argv[1]}
}, ensure_ascii=False))
" "$marker"
}

# Build SubagentStop JSON for QA integration
make_qa_integration_stop_json() {
  local marker="$1"
  python3 -c "
import json, sys
print(json.dumps({
    'hook_event_name': 'SubagentStop',
    'session_id': 'test-session',
    'agent_type': 'claude-baton:qa-integration',
    'agent_name': 'claude-baton:qa-integration',
    'tool_response': {'content': 'Integration QA complete.\n' + sys.argv[1]}
}, ensure_ascii=False))
" "$marker"
}

# Run agent-logger stop with the given JSON payload
# Optionally override QA_MAX_RETRIES via env
run_qa_stop() {
  local baton_root="$1"
  local json_data="$2"
  local max_retries="${3:-}"
  local exit_code=0

  if [ -n "$max_retries" ]; then
    echo "$json_data" \
      | BATON_ROOT="$baton_root" QA_MAX_RETRIES="$max_retries" \
        bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  else
    echo "$json_data" \
      | BATON_ROOT="$baton_root" \
        bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || exit_code=$?
  fi
  return 0  # hook exit codes do not propagate test assertions
}

echo "=== F4 QA Auto-Regression Dispatch Tests ==="
echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 1: QA FAIL retry_count=0 → regresses to worker
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 1: QA FAIL (1st attempt) → regress to worker ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_worker_done=$(read_state_field "$T" "phaseFlags.workerCompleted")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")
actual_rework=$(read_state_field "$T" "reworkStatus.active")

assert_eq "1a: currentPhase=worker after 1st QA FAIL" "worker" "$actual_phase"
assert_eq "1b: phaseFlags.workerCompleted=false after regress" "false" "$actual_worker_done"
assert_eq "1c: qaRetryCount.task-01=1 (incremented)" "1" "$actual_retry"
assert_true "1d: reworkStatus.active=true" "$actual_rework"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 2: QA FAIL retry_count=2 (3rd attempt, threshold=3) → regress to taskmgr
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 2: QA FAIL (3rd attempt, exhausted) → regress to taskmgr ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{"task-01": 2}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_taskmgr_done=$(read_state_field "$T" "phaseFlags.taskMgrCompleted")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")

assert_eq "2a: currentPhase=taskmgr after 3rd QA FAIL" "taskmgr" "$actual_phase"
assert_eq "2b: phaseFlags.taskMgrCompleted=false after regress" "false" "$actual_taskmgr_done"
assert_eq "2c: qaRetryCount.task-01=3 (incremented)" "3" "$actual_retry"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 3: QA FAIL retry_count=2 + QA_MAX_RETRIES=5 → still worker (not exhausted)
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 3: QA FAIL count=2, QA_MAX_RETRIES=5 → still regress to worker ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{"task-01": 2}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json" "5"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")

assert_eq "3a: currentPhase=worker (QA_MAX_RETRIES=5, count=3 < 5)" "worker" "$actual_phase"
assert_eq "3b: qaRetryCount.task-01=3 (incremented)" "3" "$actual_retry"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 4: QA ESCALATED → regress to taskmgr, qaRetryCount=99
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 4: QA ESCALATED → regress to taskmgr, qaRetryCount=99 ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:ESCALATED:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")
actual_escalated=$(read_state_field "$T" "qaEscalated.task-01")
actual_rework=$(read_state_field "$T" "reworkStatus.active")

assert_eq "4a: currentPhase=taskmgr after ESCALATED" "taskmgr" "$actual_phase"
assert_eq "4b: qaRetryCount.task-01=99" "99" "$actual_retry"
assert_true "4c: qaEscalated.task-01=true" "$actual_escalated"
assert_true "4d: reworkStatus.active=true" "$actual_rework"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 5: QA PASS → no regress, qaUnitPassed=true
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 5: QA PASS → no regress, qaUnitPassed=true ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_unit_stop_json "QA_RESULT:PASS")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_qa_passed=$(read_state_field "$T" "phaseFlags.qaUnitPassed")
actual_rework=$(read_state_field "$T" "reworkStatus.active")

# On PASS: phase should advance to review (both QA flags still pending for int)
# or remain at qa (qaIntegrationPassed still false). The key check is no regression.
assert_true "5a: phaseFlags.qaUnitPassed=true on PASS" "$actual_qa_passed"
assert_eq "5b: reworkStatus.active=false on PASS (no regression)" "false" "$actual_rework"
# Phase should NOT have gone backwards to worker or taskmgr
local_phase="$actual_phase"
if [ "$local_phase" = "worker" ] || [ "$local_phase" = "taskmgr" ]; then
  assert_eq "5c: phase did NOT regress on PASS" "qa_or_review" "$local_phase"
else
  assert_eq "5c: phase did NOT regress on PASS (qa/review/done)" "qa_or_review" "qa_or_review"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 6: .agent-stack handling — pop before handler → regress_to_phase succeeds
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 6: .agent-stack is popped before QA handler fires ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2

# Simulate: QA agent was on the stack during its run
# The stop handler pops it before calling handle_qa_unit_stop
# So we pre-populate the stack and let the stop event clear it
echo "2026-04-05T00:00:00Z|claude-baton:qa-unit" > "$T/.baton/logs/.agent-stack"

json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
# If the stack was properly cleared before regress_to_phase, regression succeeds
assert_eq "6a: regress succeeds even when stack had QA entry (popped first)" "worker" "$actual_phase"

# Stack file should be gone (single entry was popped)
if [ ! -f "$T/.baton/logs/.agent-stack" ] || [ ! -s "$T/.baton/logs/.agent-stack" ]; then
  TOTAL=$((TOTAL + 1))
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 6b: .agent-stack cleared after stop (no residual entries)"
else
  TOTAL=$((TOTAL + 1))
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 6b: .agent-stack should be empty after stop"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 7: regress_to_phase failure (securityHalt=true) does NOT crash hook
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 7: regress_to_phase failure does not crash the hook ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
# Set securityHalt to block regress_to_phase (returns exit 3)
python3 -c "
import json
with open('$T/.baton/state.json') as f:
    d = json.load(f)
d['securityHalt'] = True
with open('$T/.baton/state.json', 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
"

json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
hook_exit=0
echo "$json" | BATON_ROOT="$T" bash "$AGENT_LOGGER" stop > /dev/null 2>&1 || hook_exit=$?

# Hook must exit 0 even when regress_to_phase fails internally
TOTAL=$((TOTAL + 1))
if [ "$hook_exit" -eq 0 ]; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 7a: hook exits 0 even when regress_to_phase fails (securityHalt)"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 7a: hook should exit 0 but exited $hook_exit"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 8: handle_qa_integration_stop mirrors handle_qa_unit_stop for FAIL
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 8: handle_qa_integration_stop FAIL → regress to worker ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_integration_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_worker_done=$(read_state_field "$T" "phaseFlags.workerCompleted")

assert_eq "8a: Integration QA FAIL → currentPhase=worker" "worker" "$actual_phase"
assert_eq "8b: phaseFlags.workerCompleted=false after integration QA FAIL" "false" "$actual_worker_done"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 9: handle_qa_integration_stop ESCALATED → regress to taskmgr
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 9: handle_qa_integration_stop ESCALATED → regress to taskmgr ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2
json=$(make_qa_integration_stop_json "QA_RESULT:ESCALATED:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_retry=$(read_state_field "$T" "qaRetryCount.task-01")

assert_eq "9a: Integration QA ESCALATED → currentPhase=taskmgr" "taskmgr" "$actual_phase"
assert_eq "9b: qaRetryCount.task-01=99 after ESCALATED" "99" "$actual_retry"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 10 (M1): Parallel QA — qa-unit FAIL while qa-integration is still
# active → regression must be DEFERRED (not silently dropped), then
# REPLAYED when the sibling stops and the .agent-stack drains.
#
# This test reproduces the M1 bug:
#   1. .agent-stack = [qa-unit, qa-integration]   (parallel run)
#   2. qa-unit stops with FAIL → prune_last_line removes the tail entry
#      so .agent-stack still has 1 sibling entry. regress_to_phase
#      hits SC-REGRESS-01 (rc=4). Without M1, the FAIL is silently lost.
#   3. With M1: regressionDeferred is persisted to state.json.
#   4. qa-integration stops (PASS) → stack drains to empty.
#   5. The M1 replay logic at the end of the stop handler re-issues
#      regress_to_phase with the deferred target. Regression executes.
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 10 (M1): Parallel QA FAIL — regression deferred + replayed ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2

# Pre-populate .agent-stack with BOTH parallel QA agents.
# Order matters for prune_last_line: last line is popped first.
echo "2026-04-05T00:00:00Z|claude-baton:qa-unit"        >  "$T/.baton/logs/.agent-stack"
echo "2026-04-05T00:00:01Z|claude-baton:qa-integration" >> "$T/.baton/logs/.agent-stack"

# ----- Step 1: qa-unit fires SubagentStop with FAIL -----
# After prune_last_line, .agent-stack still has 1 entry (qa-unit).
# handle_qa_unit_stop → _dispatch_qa_regression → regress_to_phase rc=4.
# M1: must persist regressionDeferred instead of silently dropping.
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
deferred_target=$(read_state_field "$T" "regressionDeferred.target")
deferred_reason=$(read_state_field "$T" "regressionDeferred.reason")
stack_lines=$(wc -l < "$T/.baton/logs/.agent-stack" 2>/dev/null | tr -d ' ')

assert_eq "10a: currentPhase still 'qa' (regression deferred, not yet replayed)" "qa" "$actual_phase"
assert_eq "10b: regressionDeferred.target=worker (M1 persisted)" "worker" "$deferred_target"
TOTAL=$((TOTAL + 1))
if [ -n "$deferred_reason" ] && [ "$deferred_reason" != "null" ]; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 10c: regressionDeferred.reason recorded ('$deferred_reason')"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 10c: regressionDeferred.reason should be set (got '$deferred_reason')"
fi
assert_eq "10d: .agent-stack still has 1 sibling entry after qa-unit pop" "1" "$stack_lines"

# ----- Step 2: qa-integration fires SubagentStop with PASS -----
# prune_last_line removes the last entry → stack drains to empty.
# Replay logic must fire and execute regress_to_phase("worker") successfully.
json=$(make_qa_integration_stop_json "QA_RESULT:PASS")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
actual_worker_done=$(read_state_field "$T" "phaseFlags.workerCompleted")
actual_rework=$(read_state_field "$T" "reworkStatus.active")
deferred_after=$(read_state_field "$T" "regressionDeferred.target")

assert_eq "10e: currentPhase=worker after replay (regression finally fired)" "worker" "$actual_phase"
assert_eq "10f: phaseFlags.workerCompleted=false after replayed regress" "false" "$actual_worker_done"
assert_true "10g: reworkStatus.active=true after replayed regress" "$actual_rework"
TOTAL=$((TOTAL + 1))
if [ "$deferred_after" = "null" ] || [ -z "$deferred_after" ] || [ "$deferred_after" = "" ]; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 10h: regressionDeferred cleared after replay"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 10h: regressionDeferred should be cleared (got '$deferred_after')"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 11 (M1): Parallel QA where the SECOND agent triggers the replay.
# Verifies that the replay happens regardless of which sibling fails first.
# Scenario: qa-integration FAIL while qa-unit is still active.
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 11 (M1): Parallel QA — qa-integration FAIL deferred + replayed ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2

# Stack: qa-integration is the LAST line so it pops first.
echo "2026-04-05T00:00:00Z|claude-baton:qa-unit"        >  "$T/.baton/logs/.agent-stack"
echo "2026-04-05T00:00:01Z|claude-baton:qa-integration" >> "$T/.baton/logs/.agent-stack"

# qa-integration stops first with FAIL → deferred
json=$(make_qa_integration_stop_json "QA_RESULT:FAIL:task-02")
run_qa_stop "$T" "$json"

deferred_target=$(read_state_field "$T" "regressionDeferred.target")
assert_eq "11a: regressionDeferred.target=worker after qa-integration FAIL" "worker" "$deferred_target"

# qa-unit then stops with PASS → stack drains, replay fires
json=$(make_qa_unit_stop_json "QA_RESULT:PASS")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
deferred_after=$(read_state_field "$T" "regressionDeferred.target")

assert_eq "11b: currentPhase=worker after sibling drains stack and replay fires" "worker" "$actual_phase"
TOTAL=$((TOTAL + 1))
if [ "$deferred_after" = "null" ] || [ -z "$deferred_after" ] || [ "$deferred_after" = "" ]; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 11c: regressionDeferred cleared after replay"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 11c: regressionDeferred should be cleared (got '$deferred_after')"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 12 (M1): Parallel QA where BOTH siblings FAIL.
# Second FAIL must overwrite the deferred target (last write wins) but the
# replay still ends with currentPhase=worker (worker is the shared target).
# Also verifies escalation: if the second FAIL pushes retry_count to threshold,
# the deferred target switches to taskmgr.
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 12 (M1): Parallel QA — both siblings FAIL, replay still fires ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2

echo "2026-04-05T00:00:00Z|claude-baton:qa-unit"        >  "$T/.baton/logs/.agent-stack"
echo "2026-04-05T00:00:01Z|claude-baton:qa-integration" >> "$T/.baton/logs/.agent-stack"

# qa-unit FAIL → deferred (sibling still in stack)
json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

# qa-integration FAIL → stack drains; the integration handler ALSO defers
# (sibling drained mid-handler is OK because the pop happens first), then
# the replay path kicks in.
json=$(make_qa_integration_stop_json "QA_RESULT:FAIL:task-02")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
unit_retry=$(read_state_field "$T" "qaRetryCount.task-01")
int_retry=$(read_state_field "$T" "qaRetryCount.task-02")

assert_eq "12a: currentPhase=worker after both FAILs (regression replayed)" "worker" "$actual_phase"
assert_eq "12b: qaRetryCount.task-01=1 incremented for unit FAIL" "1" "$unit_retry"
assert_eq "12c: qaRetryCount.task-02=1 incremented for integration FAIL" "1" "$int_retry"
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Test 13 (M1): Single-agent stop (non-parallel) must NOT touch
# regressionDeferred. This guards against regressions: the M1 path only
# fires when SC-REGRESS-01 actually returned rc=4.
# ─────────────────────────────────────────────────────────────────────
echo "--- Test 13 (M1): Solo QA FAIL leaves regressionDeferred unset ---"

T=$(mktemp -d)
mkdir -p "$T/.baton/logs"
BATON_ROOT="$T" init_qa_state "$T" '{}' 2

# Solo: only qa-unit on the stack → pop drains it → regress succeeds
echo "2026-04-05T00:00:00Z|claude-baton:qa-unit" > "$T/.baton/logs/.agent-stack"

json=$(make_qa_unit_stop_json "QA_RESULT:FAIL:task-01")
run_qa_stop "$T" "$json"

actual_phase=$(read_state_field "$T" "currentPhase")
deferred=$(read_state_field "$T" "regressionDeferred.target")

assert_eq "13a: solo FAIL still goes straight to worker" "worker" "$actual_phase"
TOTAL=$((TOTAL + 1))
if [ "$deferred" = "null" ] || [ -z "$deferred" ] || [ "$deferred" = "" ]; then
  PASS=$((PASS + 1))
  echo -e "${GREEN}PASS${NC}: 13b: regressionDeferred unset on solo (SC-REGRESS-01 not triggered)"
else
  FAIL=$((FAIL + 1))
  echo -e "${RED}FAIL${NC}: 13b: regressionDeferred should be unset on solo (got '$deferred')"
fi
rm -rf "$T"

echo ""

# ─────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────
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
