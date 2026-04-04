#!/usr/bin/env bash
# test-agent-logger-detect.sh — Tests for detect_agent_type() in agent-logger.sh
#
# Verifies:
#   1. agent_type format (claude-baton:*) is correctly mapped
#   2. Legacy description-prefix patterns still work as fallback
#   3. Unknown types return "unknown"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
  if [ "$actual" = "$expected" ]; then
    PASS=$((PASS + 1))
    echo -e "${GREEN}PASS${NC}: $test_name (expected=$expected, actual=$actual)"
  else
    FAIL=$((FAIL + 1))
    echo -e "${RED}FAIL${NC}: $test_name (expected=$expected, actual=$actual)"
  fi
}

# ---------------------------------------------------------------------------
# Source only detect_agent_type() from agent-logger.sh
# We do this by sourcing the file after stubbing out its dependencies
# ---------------------------------------------------------------------------
# Stub dependencies so sourcing agent-logger.sh doesn't fail
hook_get_field() { echo ""; }
ensure_baton_dirs() { :; }
state_get_tier() { echo "null"; }
state_get_phase() { echo "idle"; }
state_read() { echo "null"; }
state_write() { :; }
state_set_phase() { :; }
state_init() { :; }

# Stub file/dir checks
BATON_DIR="/tmp/baton-test-$$"
mkdir -p "$BATON_DIR"
BATON_LOG_DIR="$BATON_DIR/logs"
mkdir -p "$BATON_LOG_DIR"
STATE_FILE="$BATON_DIR/state.json"

# Temporarily mock find-baton-root.sh and other sourced scripts
_ORIG_SCRIPT_DIR="$SCRIPT_DIR"

# Create a temporary wrapper that defines only detect_agent_type
# by extracting it from agent-logger.sh
AGENT_LOGGER="$SCRIPT_DIR/../agent-logger.sh"

# Extract detect_agent_type function definition
DETECT_FN=$(awk '/^detect_agent_type\(\)/{found=1} found{print} found && /^\}$/{exit}' "$AGENT_LOGGER")

# Evaluate the function in this shell
eval "$DETECT_FN"

# ---------------------------------------------------------------------------
# Tests: agent_type format (claude-baton:*) — NEW patterns
# ---------------------------------------------------------------------------

assert_eq "claude-baton:security-guardian -> review" \
  "review" "$(detect_agent_type "claude-baton:security-guardian")"

assert_eq "claude-baton:quality-inspector -> review" \
  "review" "$(detect_agent_type "claude-baton:quality-inspector")"

assert_eq "claude-baton:tdd-enforcer-reviewer -> review" \
  "review" "$(detect_agent_type "claude-baton:tdd-enforcer-reviewer")"

assert_eq "claude-baton:performance-analyst -> review" \
  "review" "$(detect_agent_type "claude-baton:performance-analyst")"

assert_eq "claude-baton:standards-keeper -> review" \
  "review" "$(detect_agent_type "claude-baton:standards-keeper")"

assert_eq "claude-baton:worker-agent -> worker" \
  "worker" "$(detect_agent_type "claude-baton:worker-agent")"

assert_eq "claude-baton:qa-unit -> qa-unit" \
  "qa-unit" "$(detect_agent_type "claude-baton:qa-unit")"

assert_eq "claude-baton:qa-integration -> qa-integration" \
  "qa-integration" "$(detect_agent_type "claude-baton:qa-integration")"

assert_eq "claude-baton:analysis-agent -> analysis" \
  "analysis" "$(detect_agent_type "claude-baton:analysis-agent")"

assert_eq "claude-baton:interview-agent -> interview" \
  "interview" "$(detect_agent_type "claude-baton:interview-agent")"

assert_eq "claude-baton:planning-architect -> planning" \
  "planning" "$(detect_agent_type "claude-baton:planning-architect")"

assert_eq "claude-baton:planning-security -> planning" \
  "planning" "$(detect_agent_type "claude-baton:planning-security")"

assert_eq "claude-baton:planning-dev-lead -> planning" \
  "planning" "$(detect_agent_type "claude-baton:planning-dev-lead")"

assert_eq "claude-baton:task-manager -> taskmgr" \
  "taskmgr" "$(detect_agent_type "claude-baton:task-manager")"

assert_eq "claude-baton:issue-register -> issue-register" \
  "issue-register" "$(detect_agent_type "claude-baton:issue-register")"

assert_eq "claude-baton:main-orchestrator -> unknown" \
  "unknown" "$(detect_agent_type "claude-baton:main-orchestrator")"

# ---------------------------------------------------------------------------
# Tests: legacy description-prefix patterns (must still work as fallback)
# ---------------------------------------------------------------------------

assert_eq "legacy: analysis:foo -> analysis" \
  "analysis" "$(detect_agent_type "analysis:some agent")"

assert_eq "legacy: interview:foo -> interview" \
  "interview" "$(detect_agent_type "interview:some agent")"

assert_eq "legacy: planning:foo -> planning" \
  "planning" "$(detect_agent_type "planning:some agent")"

assert_eq "legacy: planning-foo -> planning" \
  "planning" "$(detect_agent_type "planning-security")"

assert_eq "legacy: taskmgr:foo -> taskmgr" \
  "taskmgr" "$(detect_agent_type "taskmgr:task manager")"

assert_eq "legacy: worker:foo -> worker" \
  "worker" "$(detect_agent_type "worker:task-01")"

assert_eq "legacy: qa-unit:foo -> qa-unit" \
  "qa-unit" "$(detect_agent_type "qa-unit:test suite")"

assert_eq "legacy: qa-integration:foo -> qa-integration" \
  "qa-integration" "$(detect_agent_type "qa-integration:e2e tests")"

assert_eq "legacy: security guardian:foo -> review" \
  "review" "$(detect_agent_type "security guardian:review")"

assert_eq "legacy: quality inspector:foo -> review" \
  "review" "$(detect_agent_type "quality inspector:review")"

assert_eq "legacy: tdd enforcer:foo -> review" \
  "review" "$(detect_agent_type "tdd enforcer:review")"

assert_eq "legacy: performance analyst:foo -> review" \
  "review" "$(detect_agent_type "performance analyst:check")"

assert_eq "legacy: standards keeper:foo -> review" \
  "review" "$(detect_agent_type "standards keeper:check")"

assert_eq "legacy: issue register -> issue-register" \
  "issue-register" "$(detect_agent_type "issue register some agent")"

# ---------------------------------------------------------------------------
# Tests: unknown type
# ---------------------------------------------------------------------------

assert_eq "unknown type -> unknown" \
  "unknown" "$(detect_agent_type "some-random-agent")"

assert_eq "empty string -> unknown" \
  "unknown" "$(detect_agent_type "")"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$BATON_DIR"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed out of $TOTAL total"
echo ""

if [ "$FAIL" -gt 0 ]; then
  exit 1
else
  exit 0
fi
