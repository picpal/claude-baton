#!/usr/bin/env bash
# Main Guard Hook
# Main Agent가 직접 코드 파일을 수정하는 것을 차단합니다.
# PreToolUse Hook (Edit|Write 매처)
#
# 핵심 로직:
# - Subagent 스택이 비어있으면 = Main Agent가 직접 호출
# - Main Agent는 코드 파일을 직접 수정할 수 없음
# - Worker Agent에게 위임해야 함

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"

ensure_baton_dirs

LOG_FILE="$BATON_LOG_DIR/main-guard.log"
AGENT_STACK_FILE="$BATON_LOG_DIR/.agent-stack"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 허용된 경로 패턴 (Main Agent도 수정 가능)
is_allowed_path() {
  local file_path="$1"

  # .baton/ 디렉토리 허용 (상태, 계획, 태스크 파일)
  if [[ "$file_path" == .baton/* ]] || [[ "$file_path" == */.baton/* ]]; then
    return 0
  fi

  # .claude/ 디렉토리 허용 (설정 파일)
  if [[ "$file_path" == .claude/* ]] || [[ "$file_path" == */.claude/* ]]; then
    return 0
  fi

  # CLAUDE.md 허용
  if [[ "$(basename "$file_path")" == "CLAUDE.md" ]]; then
    return 0
  fi

  # .gitignore 허용
  if [[ "$(basename "$file_path")" == ".gitignore" ]]; then
    return 0
  fi

  return 1
}

# Subagent 실행 중인지 확인
is_subagent_active() {
  if [ -f "$AGENT_STACK_FILE" ] 2>/dev/null && [ -s "$AGENT_STACK_FILE" ] 2>/dev/null; then
    return 0
  fi
  return 1
}

main() {
  local file_path
  file_path=$(hook_get_field "tool_input.file_path" 2>/dev/null || echo "")

  log "Checking: file=$file_path"

  # .baton 디렉토리가 없으면 통과 (pre-init)
  if [ ! -d "$BATON_DIR" ]; then
    log "PASSED: Pre-init (no .baton dir)"
    exit 0
  fi

  # 파일 경로가 없으면 차단 (입력을 판별할 수 없음 → 안전을 위해 차단)
  if [ -z "$file_path" ]; then
    log "BLOCKED: Unable to determine file path from input"
    echo "⛔ [Main Guard] 파일 경로를 판별할 수 없습니다. 안전을 위해 차단합니다."
    exit 2
  fi

  # 보호 대상 파일 차단 (subagent 여부와 무관하게 항상 차단)
  if [[ "$file_path" == */state.json ]] && [[ "$file_path" == *.baton/* || "$file_path" == .baton/* ]]; then
    log "DENIED: Protected pipeline file ($file_path)"
    echo "⛔ [Main Guard] state.json and .agent-stack are protected pipeline files. Direct modification is not allowed."
    exit 2
  fi
  if [[ "$file_path" == *.agent-stack* ]]; then
    log "DENIED: Protected pipeline file ($file_path)"
    echo "⛔ [Main Guard] state.json and .agent-stack are protected pipeline files. Direct modification is not allowed."
    exit 2
  fi

  # Subagent 실행 중이면 통과 (Worker가 실행 중)
  if is_subagent_active; then
    local active_agent
    active_agent=$(tail -1 "$AGENT_STACK_FILE" 2>/dev/null | cut -d'|' -f2 || echo "unknown")
    log "PASSED: Subagent active ($active_agent)"
    exit 0
  fi

  # 허용된 경로이면 통과
  if is_allowed_path "$file_path"; then
    log "PASSED: Allowed path ($file_path)"
    exit 0
  fi

  # Main Agent가 코드 파일을 직접 수정하려고 함 → 차단
  log "BLOCKED: Main Agent attempted to modify code file: $file_path"

  cat <<EOF
⛔ [Main Guard] R01 위반 감지!

Main Orchestrator는 코드 파일을 직접 수정할 수 없습니다.

차단된 파일: $file_path

허용된 경로:
  - .baton/**/* (파이프라인 상태, 계획, 태스크)
  - .claude/**/* (설정)
  - CLAUDE.md (규칙)
  - .gitignore

올바른 방법:
  Agent(subagent_type="general-purpose",
        description="Worker: {작업명}",
        model="opus" or "sonnet",
        prompt="...")

코드 수정은 반드시 Worker Agent에게 위임하세요.
EOF

  exit 2
}

main
