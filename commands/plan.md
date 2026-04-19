---
name: baton:plan
description: |
  Manually trigger Phase 3: Planning.
  플래닝 단계를 수동 실행합니다. Tier별 플래너 수 자동 결정.
---

# /baton:plan

Phase 3: 플래닝을 수동으로 실행합니다.

## Prerequisites
- .baton/ 디렉토리 존재
- **필수**: .baton/complexity-score.md (없으면 경고: "/baton:analyze를 먼저 실행하세요")

## Flag Reconciliation
```bash
source hooks/scripts/state-manager.sh
# complexity-score.md 존재 시 선행 flag 설정
if [ -f .baton/complexity-score.md ]; then
  state_write "phaseFlags.analysisCompleted" "true"
fi
if [ -f .baton/issue.md ]; then
  state_write "phaseFlags.issueRegistered" "true"
fi
```

## Steps

1. state.json 읽기 — currentTier 확인
2. Tier 1이면 경고 (플래닝은 Tier 2/3 전용)
3. Flag Reconciliation 실행
4. currentPhase를 "planning"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "planning"
```
5. Tier별 플래너 에이전트 스폰:
   - **Tier 2**: planning-dev-lead 1명
   - **Tier 3**: planning-security + planning-architect + planning-dev-lead 3명 병렬

## Output
- .baton/plan.md (아키텍처 설계, 컴포넌트 정의)
- state.json: phaseFlags.planningCompleted = true
