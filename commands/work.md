---
name: baton:work
description: |
  Manually trigger Phase 5: Workers.
  워커 실행 단계를 수동 실행합니다. 완료 후 자동으로 QA 연쇄.
---

# /baton:work

Phase 5: 워커를 수동으로 실행합니다.

> **TDD 보호**: 워커 완료 후 qa-unit이 자동으로 연쇄 실행됩니다 (autoMode와 무관).

## Prerequisites
- .baton/ 디렉토리 존재
- **필수**: .baton/todo.md (없으면 경고: "/baton:tasks를 먼저 실행하세요")
- **필수**: .baton/complexity-score.md (없으면 경고: "/baton:analyze를 먼저 실행하세요")

## Flag Reconciliation
```bash
source hooks/scripts/state-manager.sh
if [ -f .baton/complexity-score.md ]; then
  state_write "phaseFlags.analysisCompleted" "true"
fi
if [ -f .baton/plan.md ]; then
  state_write "phaseFlags.planningCompleted" "true"
fi
if [ -f .baton/todo.md ]; then
  state_write "phaseFlags.taskMgrCompleted" "true"
fi
if [ -f .baton/issue.md ]; then
  state_write "phaseFlags.issueRegistered" "true"
fi
```

## Steps

1. Flag Reconciliation 실행
2. .baton/todo.md 읽기 — 미완료 태스크 확인
3. currentPhase를 "worker"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "worker"
```
4. 태스크별 Worker 에이전트 병렬 스폰:
   - 각 태스크의 stack 태그에 따라 baton-tdd-{stack} 스킬 주입
   - 모델: files ≤ 3 → sonnet, files > 3 또는 cross-service → opus
   - scope-lock 적용 (할당된 파일만 수정 가능)
5. 모든 Worker 완료 후 → qa-unit 자동 연쇄 실행 (TDD 최소 검증)

## Output
- TDD 기반 커밋 (RED→GREEN→REFACTOR)
- state.json: phaseFlags.workerCompleted = true
- → 자동으로 Phase 6 (QA) 진행
