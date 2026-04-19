---
name: baton:tasks
description: |
  Manually trigger Phase 4: Task Manager.
  태스크 분할 단계를 수동 실행합니다.
---

# /baton:tasks

Phase 4: 태스크 매니저를 수동으로 실행합니다.

## Prerequisites
- .baton/ 디렉토리 존재
- **필수**: .baton/plan.md (없으면 경고: "/baton:plan을 먼저 실행하세요")
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
if [ -f .baton/issue.md ]; then
  state_write "phaseFlags.issueRegistered" "true"
fi
```

## Steps

1. Flag Reconciliation 실행
2. currentPhase를 "taskmgr"로 설정:
```bash
source hooks/scripts/state-manager.sh && state_set_phase "taskmgr"
```
3. `task-manager` 에이전트 스폰 (model: opus)
   - baton-task-splitter 스킬 주입
   - plan.md를 독립 태스크로 분할
   - 각 태스크에 스택별 baton-tdd-{stack} 스킬 태깅

## Output
- .baton/todo.md (태스크 목록, 스택 태그, 의존성)
- TaskCreate로 태스크 등록
- WORKER_COUNT:{N} 마커 출력
- state.json: phaseFlags.taskMgrCompleted = true
