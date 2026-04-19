---
name: baton:interview
description: |
  Manually trigger Phase 1: Interview.
  인터뷰 단계를 수동 실행합니다. Tier 2/3 전용.
---

# /baton:interview

Phase 1: 인터뷰를 수동으로 실행합니다.

## Prerequisites
- .baton/ 디렉토리 존재
- 선행 아티팩트: .baton/issue.md (선택 — 없으면 경고)

## Flag Reconciliation
```bash
# issue.md 존재 시 선행 flag 설정
if [ -f .baton/issue.md ]; then
  source hooks/scripts/state-manager.sh && state_write "phaseFlags.issueRegistered" "true"
fi
```

## Steps

1. state.json 읽기 — currentTier 확인
2. Tier 1이면 경고 출력 (인터뷰는 Tier 2/3 전용)
3. Flag Reconciliation 실행
4. currentPhase를 "interview"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "interview"
```
5. `interview-agent` 에이전트 스폰

## Output
- 확인된 요구사항 (에이전트 출력)
- state.json: phaseFlags.interviewCompleted = true
