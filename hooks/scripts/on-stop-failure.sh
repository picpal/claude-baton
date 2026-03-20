#!/bin/bash
# API 에러로 에이전트가 중단되었을 때 자동 로깅

[ -d ".baton" ] || exit 0

LOG_DIR=".baton/logs"
mkdir -p "$LOG_DIR"
echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] STOP_FAILURE: Agent stopped due to API error" >> "$LOG_DIR/exec.log"
echo "[baton] StopFailure logged to $LOG_DIR/exec.log"
