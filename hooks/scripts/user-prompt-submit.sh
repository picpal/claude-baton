#!/usr/bin/env bash
# Baton UserPromptSubmit Hook — Intent 분류 + 파이프라인 상태 주입

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"
source "$SCRIPT_DIR/state-manager.sh"

# .baton이 없으면 스킵
[ -d "$BATON_DIR" ] || exit 0

# Stale agent-stack detection — prune zombie entries on every prompt
PRUNED_COUNT=$(prune_stale_stack_entries "$BATON_LOG_DIR/.agent-stack" 2>/dev/null || echo 0)

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

LAST_PHASE_FILE="$BATON_DIR/logs/.last-prompt-phase"
LAST_PHASE=""
if [ -f "$LAST_PHASE_FILE" ]; then
  LAST_PHASE=$(cat "$LAST_PHASE_FILE" 2>/dev/null)
fi

# Read tracker progress for current phase
TRACKER_PROGRESS=""
if [ -f "$BATON_DIR/state.json" ]; then
  case "$PHASE" in
    review)
      R_DONE=$(state_array_len "reviewTracker.completed" 2>/dev/null || echo "0")
      R_EXPECTED=$(state_read "reviewTracker.expected" 2>/dev/null || echo "0")
      [ "$R_EXPECTED" != "null" ] && [ "$R_EXPECTED" != "0" ] && TRACKER_PROGRESS="rev(${R_DONE}/${R_EXPECTED})"
      ;;
    worker)
      W_DONE=$(state_read "workerTracker.doneCount" 2>/dev/null || echo "0")
      W_EXPECTED=$(state_read "workerTracker.expected" 2>/dev/null || echo "0")
      [ "$W_EXPECTED" != "null" ] && [ "$W_EXPECTED" != "0" ] && TRACKER_PROGRESS="wrk(${W_DONE}/${W_EXPECTED})"
      ;;
    planning)
      P_DONE=$(state_array_len "planningTracker.completed" 2>/dev/null || echo "0")
      P_EXPECTED=$(state_read "planningTracker.expected" 2>/dev/null || echo "0")
      [ "$P_EXPECTED" != "null" ] && [ "$P_EXPECTED" != "0" ] && TRACKER_PROGRESS="pln(${P_DONE}/${P_EXPECTED})"
      ;;
  esac
fi

if [ -n "$TRACKER_PROGRESS" ]; then
  PROGRESS_DISPLAY="${TRACKER_PROGRESS}|${DONE}/${TOTAL}"
else
  PROGRESS_DISPLAY="${DONE}/${TOTAL}"
fi

if [ "$LAST_PHASE" = "$PHASE" ]; then
  # Same phase — output 1-line summary only
  if [ "${PRUNED_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo "[Baton] ⚠ Cleaned ${PRUNED_COUNT} stale agent-stack entries (TTL=2h)"
  fi
  cat <<EOF
<user-prompt-submit-hook>
[Baton] T:${TIER}|P:${PHASE}|${PROGRESS_DISPLAY}
</user-prompt-submit-hook>
EOF
else
  # Phase changed or first run — output full block and update cache
  mkdir -p "$(dirname "$LAST_PHASE_FILE")"
  printf '%s' "$PHASE" > "$LAST_PHASE_FILE"
  if [ "${PRUNED_COUNT:-0}" -gt 0 ] 2>/dev/null; then
    echo "[Baton] ⚠ Cleaned ${PRUNED_COUNT} stale agent-stack entries (TTL=2h)"
  fi
  cat <<EOF
<user-prompt-submit-hook>
[Baton] Tier: ${TIER} | Phase: ${PHASE} | Tasks: ${PROGRESS_DISPLAY}

Intent 분류 후 행동:
A) NEW_TASK — 새 개발 요청 → Analysis Agent 즉시 스폰 (state를 idle로 리셋)
B) CONTINUE — 파이프라인 재개:
   1. Read .baton/state.json → currentPhase, phaseFlags 확인
   2. Read .baton/complexity-score.md, todo.md, plan.md → 맥락 복원
   3. 첫 번째 false flag = 재개 지점 → 해당 phase 에이전트 스폰
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
fi
