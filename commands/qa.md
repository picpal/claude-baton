---
name: baton:qa
description: |
  Manually trigger Phase 6: QA.
  QA 단계를 수동 실행합니다. Unit + Integration 병렬.
---

# /baton:qa

Phase 6: QA를 수동으로 실행합니다.

## Prerequisites
- .baton/ 디렉토리 존재
- **필수**: phaseFlags.workerCompleted = true (없으면 경고: "/baton:work를 먼저 실행하세요")

## Flag Reconciliation
```bash
source hooks/scripts/state-manager.sh
WORKER_DONE=$(state_read "phaseFlags.workerCompleted")
if [ "$WORKER_DONE" != "true" ]; then
  echo "⚠️ [baton:qa] workerCompleted=false — /baton:work를 먼저 실행하세요"
fi
```

## Steps

1. state.json 읽기 — currentTier 확인
2. currentPhase를 "qa"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "qa"
```
3. QA 에이전트 병렬 스폰:
   - **qa-unit**: 유닛 테스트 실행, 커버리지 80%+ 확인
   - **qa-integration**: (Tier 2/3) 통합 테스트, API 계약 검증
   - Tier 1: qa-unit만 실행
4. 실패 시 최대 3회 재시도 → 초과 시 TaskMgr로 에스컬레이션

## Output
- QA_RESULT:PASS 또는 QA_RESULT:FAIL:{reason}
- state.json: phaseFlags.qaUnitPassed = true, phaseFlags.qaIntegrationPassed = true
- safe/task-{id} 태그 생성 (Unit QA 통과 시)
