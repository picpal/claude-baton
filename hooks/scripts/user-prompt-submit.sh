#!/usr/bin/env bash
# Baton UserPromptSubmit Hook — Intent 분류 + 파이프라인 상태 주입

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"
source "$SCRIPT_DIR/state-manager.sh"

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

# state.json에서 Tier/Phase 읽기
if [ -f "$BATON_DIR/state.json" ]; then
  TIER=$(state_get_tier)
  PHASE=$(state_get_phase)
  [ "$TIER" = "null" ] && TIER="?"
  [ -z "$PHASE" ] && PHASE="idle"
else
  TIER="?"
  PHASE="idle"
fi

cat <<EOF
<user-prompt-submit-hook>
[Baton] Tier: ${TIER} | Phase: ${PHASE} | Tasks: ${DONE}/${TOTAL}

Intent 분류 후 행동:
A) NEW_TASK — 새 개발 요청 → Analysis Agent 즉시 스폰 (state를 idle로 리셋)
B) CONTINUE — 파이프라인 재개 → 다음 대기 중 phase 진행
C) QUERY — 질문/상태 확인 → 직접 응답 (코드 분석 제외)
D) OVERRIDE — 사용자 수정 지시 → state 업데이트 + lesson 기록
E) COMMAND — 슬래시 명령어 → 명령어 실행

금지 행위:
- Main이 소스 코드 Read/Grep 금지 (Agent에 위임)
- Main이 직접 Edit/Write 금지 (Hook에서 차단됨)
- Main이 Bash로 코드 수정 금지 (Hook에서 차단됨)

허용 행위:
- .baton/ 파일 Read/Write (파이프라인 상태)
- Agent 스폰 (분석, 계획, 워커, QA, 리뷰)
- git 명령어 (태그, 커밋)
</user-prompt-submit-hook>
EOF
