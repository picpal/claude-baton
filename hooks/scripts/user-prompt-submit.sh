#!/usr/bin/env bash
# Baton UserPromptSubmit Hook — 파이프라인 즉시 실행 지시

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

즉시 실행: Analysis Agent를 스폰하여 복잡도 점수를 산출하세요.
소스 코드를 직접 읽거나 분석하지 마세요. 모든 작업은 Agent에 위임합니다.

금지 행위:
- Main이 소스 코드 Read/Grep 금지 (Agent에 위임)
- Main이 직접 Edit/Write 금지 (Hook에서 차단됨)
- Main이 Bash로 코드 수정 금지

허용 행위:
- .baton/ 파일 Read/Write (파이프라인 상태)
- Agent 스폰 (분석, 계획, 워커, QA, 리뷰)
- git 명령어 (태그, 커밋)
</user-prompt-submit-hook>
EOF
