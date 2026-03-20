#!/usr/bin/env bash
# Baton UserPromptSubmit Hook — 파이프라인 프로토콜 리마인더

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"

# .baton이 없으면 스킵
[ -d "$BATON_DIR" ] || exit 0

USER_PROMPT=$(hook_get_field "user_prompt")

# 슬래시 커맨드는 스킵
if echo "$USER_PROMPT" | grep -qE '^/'; then
  exit 0
fi

# 진행 상황
TOTAL="0"
DONE="0"
if [ -f "$BATON_DIR/todo.md" ] && [ -s "$BATON_DIR/todo.md" ]; then
  TOTAL=$(grep -cE '^\s*-\s*\[' "$BATON_DIR/todo.md" 2>/dev/null || echo "0")
  DONE=$(grep -cE '^\s*-\s*\[x\]' "$BATON_DIR/todo.md" 2>/dev/null || echo "0")
fi

cat <<EOF
<user-prompt-submit-hook>
[Baton] Tasks: ${DONE}/${TOTAL}
개발 요청 → Analysis Agent 스폰하여 복잡도 점수 산출 → Tier 결정 → 파이프라인 자동 진행.
코드 수정은 Worker Agent에 위임. Main 직접 수정 금지.
</user-prompt-submit-hook>
EOF
