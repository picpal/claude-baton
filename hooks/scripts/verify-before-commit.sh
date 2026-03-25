#!/usr/bin/env bash
# Verify Before Commit Hook
# 코드 리뷰가 완료되지 않은 상태에서 git commit을 차단합니다.
# PreToolUse Hook (Bash 매처)
#
# 핵심 로직:
# - git commit 명령 감지
# - Tier 1: qaUnitPassed 필요
# - Tier 2/3: reviewCompleted 필요
# - reworkStatus.active == true이면 허용

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"
source "$SCRIPT_DIR/state-manager.sh"

ensure_baton_dirs

LOG_FILE="$BATON_LOG_DIR/verify-before-commit.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if command is a real git commit (not echoed, grepped, etc.)
is_real_git_commit() {
  local cmd="$1"

  # Skip: echo/printf containing "git commit"
  if [[ "$cmd" =~ ^[[:space:]]*(echo|printf)[[:space:]] ]]; then
    return 1
  fi

  # Skip: grep/rg/ag searching for "git commit"
  if [[ "$cmd" =~ ^[[:space:]]*(grep|rg|ag|egrep|fgrep)[[:space:]] ]]; then
    return 1
  fi

  # Skip: commands where git commit is inside quotes after echo/cat
  if [[ "$cmd" =~ (echo|printf|cat)[[:space:]].*[\"\'].*git[[:space:]]commit ]]; then
    return 1
  fi

  # Match: git commit (direct)
  if [[ "$cmd" =~ (^|[;&|[:space:]])git[[:space:]]commit ]]; then
    return 0
  fi

  # Match: git -c ... commit
  if [[ "$cmd" =~ (^|[;&|[:space:]])git[[:space:]]+-c[[:space:]] ]] && [[ "$cmd" =~ [[:space:]]commit ]]; then
    return 0
  fi

  return 1
}

main() {
  # .baton 디렉토리가 없으면 통과 (pre-init)
  if [ ! -d "$BATON_DIR" ]; then
    log "PASSED: Pre-init (no .baton dir)"
    exit 0
  fi

  local command
  command=$(hook_get_field "tool_input.command" || echo "")

  log "Checking: command=${command:0:100}"

  # 명령어가 비어있으면 통과
  if [ -z "$command" ]; then
    log "PASSED: Empty command"
    exit 0
  fi

  # git commit이 아니면 통과
  if ! is_real_git_commit "$command"; then
    log "PASSED: Not a git commit command"
    exit 0
  fi

  log "Git commit detected, checking state..."

  # Rework 상태이면 허용
  local rework_active
  rework_active=$(state_read "reworkStatus.active" || echo "")
  if [ "$rework_active" = "true" ]; then
    log "PASSED: Rework commit allowed"
    exit 0
  fi

  # Tier 확인
  local tier
  tier=$(state_get_tier || echo "")

  # Init-phase exemption: tier=null/0 means no pipeline has been started yet.
  # Allow commits during baton:init (state.json created but pipeline not yet assigned a tier).
  # Security note: this check is intentionally gated on tier being null/0 —
  # setting phase=idle alone cannot bypass the gate if a real tier is already assigned.
  if [ "$tier" = "null" ] || [ -z "$tier" ] || [ "$tier" = "0" ]; then
    local phase
    phase=$(state_get_phase || echo "")
    if [ "$phase" = "idle" ] || [ "$phase" = "null" ] || [ -z "$phase" ]; then
      log "PASSED: Init-phase exemption (tier=$tier, phase=$phase) — pipeline not yet started"
      exit 0
    fi
    log "BLOCKED: Cannot determine tier — defaulting to block for safety"
    cat <<EOF
⛔ [Commit Guard] Cannot determine pipeline tier — commit blocked for safety.

state.json may be missing or corrupt. Ensure the pipeline is initialized.
EOF
    exit 2
  fi

  # 상태 플래그 읽기
  local qa_unit qa_integration review_completed
  qa_unit=$(state_read "phaseFlags.qaUnitPassed" || echo "")
  qa_integration=$(state_read "phaseFlags.qaIntegrationPassed" || echo "")
  review_completed=$(state_read "phaseFlags.reviewCompleted" || echo "")

  local qa_unit_display qa_integration_display review_display
  qa_unit_display=$( [ "$qa_unit" = "true" ] && echo "pass" || echo "pending" )
  qa_integration_display=$( [ "$qa_integration" = "true" ] && echo "pass" || echo "pending" )
  review_display=$( [ "$review_completed" = "true" ] && echo "pass" || echo "pending" )

  local blocked=false
  local requirement=""

  case "$tier" in
    1)
      if [ "$qa_unit" != "true" ]; then
        blocked=true
        requirement="QA Unit 통과"
      fi
      ;;
    2|3)
      if [ "$review_completed" != "true" ]; then
        blocked=true
        requirement="Code Review 완료"
      fi
      ;;
  esac

  if [ "$blocked" = "true" ]; then
    log "BLOCKED: Tier $tier commit blocked (requirement: $requirement)"

    cat <<EOF
⛔ [Commit Guard] Review not completed — commit blocked

Current state:
  Tier: $tier
  QA Unit: $qa_unit_display
  QA Integration: $qa_integration_display
  Review: $review_display

Tier $tier requires $requirement before committing.
Complete the required phases first.
EOF

    exit 2
  fi

  log "PASSED: All requirements met for Tier $tier"
  exit 0
}

main
