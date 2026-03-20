# .baton/ Shared Artifact Store

All pipeline artifacts are stored in `.baton/` at the project root.

## File Reference

| File | Created By | Purpose |
|------|-----------|---------|
| `plan.md` | Planning phase | Design document with architecture decisions |
| `todo.md` | Task Manager | Task list with progress, stack tags, assignments |
| `complexity-score.md` | Analysis phase | Complexity score + Tier + detected stack mapping |
| `security-constraints.md` | Security Rollback | Security constraints (created only after Rollback) |
| `review-report.md` | Code Review phase | Consolidated review from all reviewers |
| `lessons.md` | Self-improvement | Lessons learned, recurrence prevention rules |
| `logs/exec.log` | All phases | Execution log (controlled by LOG_MODE) |
| `logs/prompt.log` | All phases | Full prompt dump (verbose mode only) |
| `reports/` | Security Guardian | Security reports, incident details |

## LOG_MODE Settings

| Mode | Output | When to Use |
|------|--------|-------------|
| `minimal` | Agent start/complete/error only | Production, low noise |
| `execution` | Step-by-step summary + file changes | Default |
| `verbose` | Full prompt dump + diff | Debugging |

Security issues are force-logged regardless of LOG_MODE setting.

## Self-Improvement Loop

### Lesson Trigger Events

| Trigger | Reporter | Writer | When |
|---------|----------|--------|------|
| QA 3-failure escalation | qa-unit, qa-integration | Main | task status = "escalated" |
| Code Review Critical | quality-inspector, tdd-enforcer | Main | Critical finding reported |
| Security MEDIUM | security-guardian | Main | MEDIUM rework initiated |
| Security Rollback | rollback command | rollback command | Rollback execution |
| User correction | Main (self-detect) | Main | User corrects approach or decision |

### lessons.md Entry Format

```markdown
---
### L-{YYYY-MM-DD}-{seq} | {category} | {severity}
- **trigger**: {qa-escalation|review-critical|security-medium|security-rollback|rework-success|user-correction}
- **task**: {task-id or "session-level"}
- **what happened**: {1-2 sentence problem description}
- **root cause**: {1-2 sentence cause analysis}
- **rule**: {imperative rule for future prevention}
- **files**: {related file paths or "N/A"}
```

- **category**: `tdd`, `security`, `quality`, `integration`, `architecture`, `scope`, `process`
- **severity**: `critical`, `high`, `medium`

### LESSON_REPORT Protocol

Agents report lessons by including a `LESSON_REPORT:` block in their output. Main Orchestrator is the single writer to lessons.md (except during Rollback). See each agent's `## Lesson Reporting` section for the specific report format.
