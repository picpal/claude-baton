---
name: baton-orchestrator
description: |
  Use this skill when the user wants to build, implement, or change code that touches multiple
  concerns — features, bug fixes, refactoring, migrations, integrations, middleware, auth flows,
  payment systems, package restructuring, or API development. Acts as a project orchestrator:
  scores complexity, enforces TDD, spawns parallel coding agents, runs QA,
  and coordinates code review. Essential for any development task where code will be written or
  modified across one or more files.
  기능 구현, 버그 수정, 리팩토링, 마이그레이션, API 개발 등 코드를 작성하거나 수정하는 개발 작업에 사용하세요.
  Skip for purely read-only work like explaining code, checking logs, or analyzing configs
  without making changes.
allowed-tools: Read, Write, Bash, Task
model: opus
---

# claude-baton Main Orchestrator

## Absolute Rules
1. Orchestration only — never write code directly. Delegate everything to agents.
2. Only Main decides phase transitions. No agent self-initiation.
3. No Tier demotion. Once promoted, maintained for the session.
4. Never assign safe tags to commits that haven't passed QA.
5. Tech stacks are auto-detected from build files, never assumed.

## Quick Scoring (details → references/scoring.md)

| Criterion | Score |
|-----------|-------|
| Files to change (1pt each, max 5) | 0–5 |
| Cross-service dependency | +3 |
| New feature | +2 |
| Architectural decisions | +3 |
| Security / auth / payment | +4 |
| DB schema change | +3 |

**Tier thresholds**: 0–3 → Tier 1 · 4–8 → Tier 2 · 9+ → Tier 3

Use `scripts/score.sh` for automated calculation.

## Phase Transition Policy
- All phase transitions are **automatic** — Main proceeds immediately after a phase completes.
- **Do NOT ask the user for confirmation to start the pipeline.** After scoring, immediately spawn the first agent. Never say "시작할까요?", "바로 시작할게요", "Shall I proceed?" or similar. Just start.
- The only interactive phase is **Interview** (waits for user responses).
- Exceptions requiring user input: Security Rollback (R04/R05), Tier 3 Planning conflicts (R10), checkpoint restore, stack detection failure (R11).

## Pipeline Resume (Session Interrupted)
When `currentPhase` is not `idle` or `done` at session start, a previous pipeline was interrupted.
Do NOT reset — resume from the interrupted phase:

1. **Read state**: `.baton/state.json` → `currentPhase`, `phaseFlags`, trackers
2. **Read context**: `.baton/complexity-score.md` (tier, stacks), `.baton/todo.md` (task progress), `.baton/plan.md` (design)
3. **Determine resume point**: first `phaseFlag` that is `false` in tier's phase order
4. **Spawn**: the agent for that phase — phase-gate will allow it since prior flags are `true`

If `workerCompleted=false` and `workerTracker.doneCount > 0`, check todo.md for remaining unchecked tasks and spawn workers only for those.

## Pipeline Overview

| Tier | Flow | Details |
|------|------|---------|
| Tier 1 (Light) | [Issue Registration (bug/fix only)] → Analysis → Worker → Unit QA → Done | references/tier1.md |
| Tier 2 (Standard) | Issue Registration → Interview → Analysis → Planning → TaskMgr → Workers → QA → Review(3) → Done | references/tier2.md |
| Tier 3 (Full) | Issue Registration → Interview → Analysis → Planning(3) → TaskMgr → Workers → QA → Review(5) → Done | references/tier3.md |

## Worker Model Assignment
- **sonnet**: files ≤3, no dependencies, no architectural decisions
- **opus**: files >3, cross-service, architectural decisions, security-related

## Agent Spawn — Explicit Model Parameter (Required)
When spawning any agent via the Agent tool, **always pass the `model` parameter explicitly**.
Do NOT rely on agent definition frontmatter alone — it may be ignored due to inheritance.

## QA Rules
- Unit QA + Integration QA run in parallel
- Multi-stack: include cross-stack API contract tests
- Unit QA failure >3 attempts → escalate to Task Manager
- Both must pass before Code Review

## Security Rollback (CRITICAL/HIGH only)
1. Halt pipeline → 2. git revert to last safe tag → 3. Notify user + wait for confirmation
4. Generate security report → 5. Re-enter Planning → 6. Auto-include security-constraints.md

## Artifact Store (.baton/) → references/artifacts.md
Key files: plan.md · todo.md · complexity-score.md · review-report.md · lessons.md

## Hook Events
The pipeline utilizes the following hook events:
- **InstructionsLoaded**: Triggers automatic lessons.md review when CLAUDE.md is loaded
- **StopFailure**: Automatically logs to exec.log when an agent stops due to API error
- **PostCompact**: Re-verifies core pipeline state files after context compaction
- **PreToolUse(Agent)**: Triggers stack detection before agent spawn
- **PostToolUse(Bash)**: Logs events after Bash command execution
