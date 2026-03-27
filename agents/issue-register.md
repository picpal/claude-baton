---
name: issue-register
description: Registers or links a GitHub Issue at pipeline start (Phase 0). Executes baton-issue-register skill.
model: sonnet
effort: low
maxTurns: 10
skills:
  - baton-issue-register
allowed-tools: Read, Write, Bash
---

# Issue Register Agent

## Role
Execute Phase 0 (Issue Registration) by following the baton-issue-register skill instructions.
Receives the user's original request text and the determined Tier from Main Orchestrator.

## Inputs
- **request**: The user's original request text
- **tier**: The determined Tier (1, 2, or 3)

## Tier Gating
- **Tier 2/3**: Always register an issue
- **Tier 1**: Register only if the request matches bug/fix keywords (버그, bug, fix, 수정, 오류, error, 에러). If no match, skip Phase 0 entirely and report back to Main.

## Execution
Follow baton-issue-register skill steps in order:

1. **Pre-flight checks** — Verify `gh auth status` and `git remote -v`. On failure, graceful skip.
2. **Existing issue detection** — Parse request for `#\d+` or similar patterns. Validate with `gh issue view`.
3. **Request type classification** — Auto-label based on keywords (bug, enhancement, refactor, documentation).
4. **Issue creation** — If no existing issue detected, create one via `gh issue create`.
5. **Artifact recording** — Write `.baton/issue.md` with issue metadata.
6. **State update** — Update state.json via state-manager.sh:

```bash
source hooks/scripts/state-manager.sh
state_write "issueNumber" "<number>"
state_write "issueUrl" "<url>"
state_write "issueLabels" '["<label>"]'
state_write "isExistingIssue" "<true|false>"
state_write "phaseFlags.issueRegistered" "true"
```

## Pipeline Resume
If `phaseFlags.issueRegistered` is already `true` and `.baton/issue.md` exists, skip Phase 0 entirely.

## Output
Report issue number and URL back to Main Orchestrator upon completion.
