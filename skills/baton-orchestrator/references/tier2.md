# Tier 2 — Standard Pipeline

## When to Use
Score 4–8 pts. Multi-file changes with moderate complexity.

## Pipeline Flow
```
Interview
  → Analysis (with stack detection)
    → Planning (single planner)
      → Task Manager (split & assign)
        → Workers (parallel)
          → QA (Unit + Integration, parallel)
            → Code Review (3 reviewers)
              → Done
```

## Phase Details

### Phase 1: Interview
- Clarify ambiguous requirements with user
- Confirm scope boundaries
- Identify acceptance criteria

### Phase 2: Analysis
- Run baton-stack-detector for full stack detection
- Map files to stacks
- Calculate complexity score
- Record in .baton/complexity-score.md

### Phase 3: Planning (Single Planner)
- One planning agent creates .baton/plan.md
- Define architecture approach
- Identify interfaces between components
- List files to create/modify

### Phase 4: Task Manager
- Split plan into independent tasks using baton-task-splitter
- Auto-tag each task with its stack
- Assign worker model (sonnet/opus) based on task complexity
- Write .baton/todo.md

### Phase 5: Workers (Parallel)
- Multiple workers execute tasks in parallel
- Each worker gets stack-specific TDD skill injected
- scope-lock enforced per worker
- Commit on completion (draft)

### Phase 6: QA (Parallel)
- Unit QA + Integration QA run simultaneously
- Multi-stack: include cross-stack API contract tests
- Unit QA failure >3 attempts → escalate to Task Manager
- Both must pass before proceeding

### Phase 7: Code Review (3 Reviewers)
| Reviewer | Focus |
|----------|-------|
| Security Guardian | CRITICAL/HIGH pattern detection, Rollback authority |
| Quality Inspector | Code quality, duplication, naming, complexity |
| TDD Enforcer | Test coverage, TDD compliance, edge cases |

### Tagging
- After Unit QA pass: `git tag safe/task-{id}`
- After Integration QA pass: `git tag safe/integration-{n}`
