---
name: baton:issue
description: |
  Manually trigger Phase 0: Issue Registration.
  GitHub 이슈 등록 단계를 수동 실행합니다.
---

# /baton:issue

Phase 0: 이슈 등록을 수동으로 실행합니다.

## Prerequisites
- .baton/ 디렉토리 존재 (파이프라인 초기화됨)
- 선행 아티팩트: 없음 (첫 번째 단계)

## Steps

1. state.json 읽기 — currentTier 확인
2. currentPhase를 "issue-register"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "issue-register"
```
3. `issue-register` 에이전트 스폰
   - Tier 1: bug/fix 키워드가 있을 때만 실행
   - Tier 2/3: 항상 실행

## Output
- .baton/issue.md (이슈 번호, URL, 라벨)
- state.json: phaseFlags.issueRegistered = true
