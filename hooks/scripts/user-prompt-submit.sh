#!/usr/bin/env bash
# Baton UserPromptSubmit Hook
# 매 사용자 요청마다 파이프라인 프로토콜을 Main Orchestrator에게 주입

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"

# .baton이 없으면 초기화 전이므로 스킵
[ -d "$BATON_DIR" ] || exit 0

USER_PROMPT=$(hook_get_field "user_prompt")

# 슬래시 커맨드는 파이프라인 강제 대상이 아님
if echo "$USER_PROMPT" | grep -qE '^/'; then
  exit 0
fi

# 현재 파이프라인 상태 읽기
TIER=""
PHASE=""
if [ -f "$BATON_DIR/complexity-score.md" ] && [ -s "$BATON_DIR/complexity-score.md" ]; then
  TIER=$(grep -oE 'Tier [0-9]' "$BATON_DIR/complexity-score.md" | head -1 || true)
fi

# todo.md에서 진행 상황 확인
TOTAL="0"
DONE="0"
if [ -f "$BATON_DIR/todo.md" ] && [ -s "$BATON_DIR/todo.md" ]; then
  TOTAL=$(grep -cE '^\s*-\s*\[' "$BATON_DIR/todo.md" 2>/dev/null || echo "0")
  DONE=$(grep -cE '^\s*-\s*\[x\]' "$BATON_DIR/todo.md" 2>/dev/null || echo "0")
fi

# 파이프라인 진행 중인지 확인
IN_PROGRESS="false"
if [ "$TOTAL" -gt 0 ] 2>/dev/null && [ "$DONE" -lt "$TOTAL" ] 2>/dev/null; then
  IN_PROGRESS="true"
fi

cat <<EOF
<user-prompt-submit-hook>
[Baton] ${TIER:-No Tier} | Tasks: ${DONE}/${TOTAL}

## ⛔ 필수 규칙 (위반 시 Hook에서 자동 차단)

### 차단 메커니즘
| 위반 행위 | 차단 Hook | 결과 |
|----------|----------|------|
| Main이 직접 Edit/Write (코드) | main-guard.sh | ⛔ 즉시 차단 |

### 모든 개발 요청 → 파이프라인 필수
사용자의 개발 요청(기능 추가, 버그 수정, 리팩터링 등)은 **반드시** baton 파이프라인을 통해 처리합니다.
"간단한 수정"이라도 예외 없이 파이프라인을 실행하세요.

### 파이프라인 흐름 (자동 진행)
1. **Analysis** — 복잡도 점수 산출 + 스택 감지 → Tier 결정
2. Tier에 따른 파이프라인 실행:
   - **Tier 1** (0-3점): Analysis → Worker → Unit QA → Done
   - **Tier 2** (4-8점): Interview → Analysis → Planning → TaskMgr → Worker → QA → Review → Done
   - **Tier 3** (9+점): Interview → Analysis → Planning(3) → TaskMgr → Worker → QA → Review(5) → Done
3. Interview만 사용자와 대화, 나머지는 자동 진행
4. 모든 코드 수정은 Worker Agent에 위임 (Main 직접 수정 금지)

### Agent 호출 (올바른 방법)
\`\`\`
Agent(subagent_type="general-purpose",
      description="{Phase}: {작업명}",
      model="opus" or "sonnet",
      prompt="...")
\`\`\`

### 예외 (파이프라인 불필요)
- 슬래시 커맨드 (/baton:status, /baton:checkpoint 등)
- 코드와 무관한 질문 (설명, 문서 조회 등)
- 파이프라인 상태 확인
</user-prompt-submit-hook>
EOF
