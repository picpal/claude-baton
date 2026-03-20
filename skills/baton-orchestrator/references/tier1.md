# Tier 1 — Light Pipeline

## When to Use
Score 0–3 pts. Simple, isolated changes with minimal risk.

## Pipeline Flow
```
Analysis (lightweight + stack detection)
  → Worker (single)
    → Unit QA
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
