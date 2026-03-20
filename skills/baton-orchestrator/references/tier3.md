# Tier 3 — Full Pipeline

## When to Use
Score 9+ pts. High-complexity changes involving security, architecture, or cross-service dependencies.

## Pipeline Flow
```
Interview
  → Analysis (with stack detection)
    → Planning (3 parallel planners)
      → Task Manager (split & assign)
        → Workers (parallel)
          → QA (Unit + Integration, parallel)
            → Code Review (5 reviewers)
              → Done
```

## Tier 3-Specific Rules
- **Auto-proceed**: Phases transition automatically, same as other tiers. Only Interview is interactive.
- **safe/baseline tag**: Created immediately after Planning completion
- **All workers default to opus model** unless explicitly downgraded

## Phase 3: Planning (3 Parallel Planners)

| Planner | Role | Focus |
|---------|------|-------|
| Security Architect | planning-security | Threat modeling, auth flows, data protection |
| System Architect | planning-architect | Service boundaries, data flow, scalability |
| Dev Lead | planning-dev-lead | Implementation approach, tech debt, testing strategy |

### Planning Merge Process
1. All 3 planners submit independently
2. Main Orchestrator merges into unified .baton/plan.md
3. Conflicts resolved by Main with user consultation
4. On completion: `git tag safe/baseline`

## Phase 5: Workers (Parallel)

### Worktree Isolation (Worker Phase)
- Each Worker runs in an isolated git worktree with the `isolation: "worktree"` option
- Prevents file conflicts between parallel Workers
- After completion, Main merges the branch; conflicts or inconsistencies are detected during QA/Review and the Worker is instructed to fix them

## Phase 7: Code Review (5 Reviewers)

| Reviewer | Focus | Tier 2? | Tier 3? |
|----------|-------|---------|---------|
| Security Guardian | CRITICAL/HIGH patterns, Rollback authority | Yes | Yes |
| Quality Inspector | Code quality, duplication, complexity | Yes | Yes |
| TDD Enforcer | Test coverage, TDD compliance | Yes | Yes |
| Performance Analyst | O(n²) loops, N+1 queries, optimization | No | Yes |
| Standards Keeper | Convention adherence, API documentation | No | Yes |

## Security Rollback Protocol
Trigger: Security Guardian declares CRITICAL or HIGH severity

1. **Halt**: Immediately stop all pipeline activity
2. **Revert**: `git revert` to last safe tag (bulk revert, no partial)
3. **Notify**: Alert user immediately, wait for confirmation before resuming
4. **Report**: Auto-generate .baton/reports/security-report.md
5. **Re-plan**: Re-enter Phase 3 (Planning), not Task Manager
6. **Constrain**: security-constraints.md auto-included in all subsequent spawns

### Severity Criteria
| Severity | Examples | Action |
|----------|----------|--------|
| CRITICAL | Secret exposure, auth bypass, SQLi, RCE | Rollback |
| HIGH | Privilege escalation, sensitive info logging, missing encryption | Rollback |
| MEDIUM+ | XSS, CSRF, weak validation | Standard rework |
