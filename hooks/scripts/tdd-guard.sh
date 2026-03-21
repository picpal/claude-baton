#!/usr/bin/env bash
# TDD Guard Hook
# 테스트 파일의 삭제/비우기를 차단합니다.
# PreToolUse Hook (Edit|Write 매처)
#
# 핵심 로직:
# - 테스트 파일 패턴 감지
# - Write로 빈 콘텐츠 작성 (삭제/비우기) → 차단
# - Edit로 전체 삭제 → 차단
# - 일반 편집/작성은 허용

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"

ensure_baton_dirs

LOG_FILE="$BATON_LOG_DIR/tdd-guard.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check if the file is a test file
is_test_file() {
  local file_path="$1"
  local basename
  basename=$(basename "$file_path")

  # .baton/ 경로는 제외
  if [[ "$file_path" == *.baton/* ]] || [[ "$file_path" == */.baton/* ]]; then
    return 1
  fi

  # *.test.* (e.g., foo.test.ts, bar.test.js)
  if [[ "$basename" =~ \.test\. ]]; then
    return 0
  fi

  # *.spec.* (e.g., foo.spec.ts)
  if [[ "$basename" =~ \.spec\. ]]; then
    return 0
  fi

  # *_test.* (e.g., foo_test.go, bar_test.py)
  if [[ "$basename" =~ _test\. ]]; then
    return 0
  fi

  # test_*.* (e.g., test_foo.py)
  if [[ "$basename" =~ ^test_.*\. ]]; then
    return 0
  fi

  # Files in __tests__/ directory
  if [[ "$file_path" == *__tests__/* ]]; then
    return 0
  fi

  # Files in tests/ directory (but NOT .baton/ paths — already excluded above)
  if [[ "$file_path" == */tests/* ]]; then
    return 0
  fi

  # Files in test/ directory
  if [[ "$file_path" == */test/* ]]; then
    return 0
  fi

  return 1
}

block_message() {
  local file_path="$1"

  cat <<EOF
⛔ [TDD Guard] Test file deletion blocked!

File: $file_path

Test files cannot be deleted or emptied.
Rule R03 (test-first) requires test code to be maintained.

If this test is genuinely obsolete:
  Report to Main with justification for removal.
EOF
}

main() {
  # .baton 디렉토리가 없으면 통과 (pre-init)
  if [ ! -d "$BATON_DIR" ]; then
    log "PASSED: Pre-init (no .baton dir)"
    exit 0
  fi

  local file_path
  file_path=$(hook_get_field "tool_input.file_path" || echo "")

  log "Checking: tool=$HOOK_TOOL_NAME file=$file_path"

  # 파일 경로가 없으면 통과
  if [ -z "$file_path" ]; then
    log "PASSED: No file path"
    exit 0
  fi

  # 테스트 파일이 아니면 통과
  if ! is_test_file "$file_path"; then
    log "PASSED: Not a test file ($file_path)"
    exit 0
  fi

  log "Test file detected: $file_path (tool: $HOOK_TOOL_NAME)"

  # Write tool: 빈 콘텐츠 → 삭제/비우기 → 차단
  if [ "$HOOK_TOOL_NAME" = "Write" ]; then
    local content
    content=$(hook_get_field "tool_input.content" || echo "")

    if [ -z "$content" ]; then
      log "BLOCKED: Write with empty content to test file: $file_path"
      block_message "$file_path"
      exit 2
    fi

    log "PASSED: Write with content to test file"
    exit 0
  fi

  # Edit tool: new_string이 비어있고 old_string이 전체 파일인 경우 → 차단
  if [ "$HOOK_TOOL_NAME" = "Edit" ]; then
    local new_string
    new_string=$(hook_get_field "tool_input.new_string" || echo "")

    if [ -z "$new_string" ]; then
      local old_string
      old_string=$(hook_get_field "tool_input.old_string" || echo "")

      # old_string이 존재하고 new_string이 비어있으면 삭제 시도로 간주
      if [ -n "$old_string" ]; then
        log "BLOCKED: Edit removing content from test file: $file_path"
        block_message "$file_path"
        exit 2
      fi
    fi

    log "PASSED: Edit to test file (not a deletion)"
    exit 0
  fi

  log "PASSED: Tool $HOOK_TOOL_NAME on test file (allowed)"
  exit 0
}

main
