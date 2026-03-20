---
name: baton-orchestrator
description: |
  Use this skill when the user wants to build, implement, or change code that touches multiple
  concerns — features, bug fixes, refactoring, migrations, integrations, middleware, auth flows,
  payment systems, package restructuring, or API development. Acts as a project orchestrator:
  scores complexity, enforces TDD, spawns parallel coding agents in isolated worktrees, runs QA,
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

## Pipeline Overview

| Tier | Flow | Details |
|------|------|---------|
| Tier 1 (Light) | Analysis → Worker → Unit QA → Done | references/tier1.md |
| Tier 2 (Standard) | Interview → Analysis → Planning → TaskMgr → Workers → QA → Review(3) → Done | references/tier2.md |
| Tier 3 (Full) | Interview → Analysis → Planning(3) → TaskMgr → Workers → QA → Review(5) → Done | references/tier3.md |

## Worker Model Assignment
- **sonnet**: files ≤3, no dependencies, no architectural decisions
- **opus**: files >3, cross-service, architectural decisions, security-related

## QA Rules
- Unit QA + Integration QA run in parallel
- Multi-stack: include cross-stack API contract tests
- Unit QA failure >3 attempts → escalate to Task Manager
- Both must pass before Code Review

## Worktree Isolation Strategy
- Worker 에이전트는 `isolation: "worktree"` 모드로 실행
- 각 Worker는 독립된 git worktree에서 작업하여 병렬 파일 충돌 방지
- Worker 완료 후 Main이 결과 브랜치를 머지
- QA/Review 단계에서 충돌·불일치 감지 → Main에 보고 → 해당 Worker에게 수정 지시 → QA 재실행

## Security Rollback (CRITICAL/HIGH only)
1. Halt pipeline → 2. git revert to last safe tag → 3. Notify user + Ask Mode ON
4. Generate security report → 5. Re-enter Planning → 6. Auto-include security-constraints.md

## Artifact Store (.baton/) → references/artifacts.md
Key files: plan.md · todo.md · complexity-score.md · review-report.md · lessons.md

## Hook Events
파이프라인은 다음 Hook 이벤트를 활용합니다:
- **InstructionsLoaded**: CLAUDE.md 로드 시 lessons.md 자동 리뷰 트리거
- **StopFailure**: API 에러로 에이전트 중단 시 exec.log에 자동 기록
- **PostCompact**: 컨텍스트 압축 후 핵심 파이프라인 상태 파일 재확인
- **WorktreeCreate/Remove**: Worker worktree 생성·제거 시 이벤트 로깅
- **PreToolUse(Agent)**: 에이전트 스폰 전 스택 감지 트리거
- **PostToolUse(Bash)**: Bash 명령 실행 후 이벤트 로깅
