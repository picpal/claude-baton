#!/bin/bash
# API 에러로 에이전트가 중단되었을 때 자동 로깅 + agent-stack 정리
#
# SubagentStop이 발화하지 않으면 agent-logger.sh가 stack을 정리하지 못함.
# stale 엔트리가 남으면 main-guard가 "subagent active"로 오판정함.

[ -d ".baton" ] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/state-manager.sh"

LOG_DIR=".baton/logs"
mkdir -p "$LOG_DIR"
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] STOP_FAILURE: Agent stopped due to API error" >> "$LOG_DIR/exec.log"

# Clean stale agent-stack entry (same logic as agent-logger.sh stop)
AGENT_STACK_FILE="$LOG_DIR/.agent-stack"
if [ -f "$AGENT_STACK_FILE" ]; then
  prune_last_line "$AGENT_STACK_FILE"
  [ -s "$AGENT_STACK_FILE" ] || rm -f "$AGENT_STACK_FILE"
fi

echo "[baton] StopFailure: logged + agent-stack cleaned"
