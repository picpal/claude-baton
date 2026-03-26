# Tier 1 — Light Pipeline

## When to Use
Score 0–3 pts. Simple, isolated changes with minimal risk.

## Phase 0: Issue Registration (bug/fix only)
- Triggered only when request contains bug/fix keywords (버그, bug, fix, 수정, 오류, error, 에러)
- Auto-create GitHub Issue or link existing one (#N)
- Auto-label as `bug`
- Record in .baton/issue.md and state.json
- If not a bug/fix request, this phase is skipped entirely

## Pipeline Flow
```
[Issue Registration (bug/fix only)]
  → Analysis (lightweight + stack detection)
    → Worker (single, TDD enforced)
      → Unit QA (80%+ coverage)
        → Done
```

## Skipped Phases
- Interview (requirements are clear from the request)
- Planning (no design decisions needed)
- Task Manager (single task, no splitting needed)
- Code Review (low risk, QA sufficient)

## Phase Details

### Analysis
- Run baton-stack-detector to identify tech stacks
- Identify affected files (should be ≤3)
- Record in .baton/complexity-score.md

### Worker
- Single worker assigned
- Model: sonnet (default for Tier 1)
- TDD enforced: test code before implementation
- scope-lock active: only modify assigned files

### Unit QA
- Run test suite for affected stack
- Coverage threshold: 80%+
- Max 3 retry attempts before escalation
- On pass: mark task complete

## No Tags
Tier 1 does not create safe/task tags (overhead not justified for simple changes).
