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

| Trigger | Action |
|---------|--------|
| User correction | Update lessons.md with the correction |
| Session start | Review lessons.md before any work |
| Security Rollback | Add pattern to security-constraints.md |
