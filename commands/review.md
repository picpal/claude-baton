---
name: baton:review
description: |
  Manually trigger Phase 7: Code Review.
  코드 리뷰 단계를 수동 실행합니다. Tier별 리뷰어 수 자동 결정.
---

# /baton:review

Phase 7: 코드 리뷰를 수동으로 실행합니다.

## Prerequisites
- .baton/ 디렉토리 존재
- **필수**: phaseFlags.qaUnitPassed = true AND phaseFlags.qaIntegrationPassed = true
  (없으면 경고: "/baton:qa를 먼저 실행하세요")

## Flag Reconciliation
```bash
source hooks/scripts/state-manager.sh
QA_UNIT=$(state_read "phaseFlags.qaUnitPassed")
QA_INT=$(state_read "phaseFlags.qaIntegrationPassed")
if [ "$QA_UNIT" != "true" ] || [ "$QA_INT" != "true" ]; then
  echo "⚠️ [baton:review] QA 미통과 — /baton:qa를 먼저 실행하세요"
fi
```

## Steps

1. state.json 읽기 — currentTier 확인
2. Tier 1이면 경고 (리뷰는 Tier 2/3 전용)
3. currentPhase를 "review"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "review"
```
4. Tier별 리뷰어 에이전트 병렬 스폰:
   - **Tier 2 (3명)**: security-guardian, quality-inspector, tdd-enforcer-reviewer
   - **Tier 3 (5명)**: + performance-analyst, standards-keeper
5. Critical 발견 시 → Worker 단계로 regression 자동 실행

## Output
- .baton/review-report.md (통합 리뷰 결과)
- state.json: phaseFlags.reviewCompleted = true
- safe/ship 태그 생성 (모두 Pass 시)
