---
name: baton:analyze
description: |
  Manually trigger Phase 2: Analysis.
  분석 단계를 수동 실행합니다. 스택 감지 + 복잡도 스코어링.
---

# /baton:analyze

Phase 2: 분석을 수동으로 실행합니다.

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

1. Flag Reconciliation 실행
2. currentPhase를 "analysis"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "analysis"
```
3. `analysis-agent` 에이전트 스폰 (model: opus)
   - baton-stack-detector 스킬 주입
   - 스택 자동 감지, 영향 분석, 복잡도 스코어링 수행

## Output
- .baton/complexity-score.md (Tier 결정, 스택 매핑, 파일 영향도)
- state.json: currentTier 설정, phaseFlags.analysisCompleted = true
- TIER:{N} 마커 출력
