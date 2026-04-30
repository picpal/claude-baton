🌐 [한국어](README.ko.md) | **English**

# claude-baton

Multi-agent development pipeline plugin for Claude Code.

Orchestrates the full development lifecycle — from requirements interview to security review — across 12 tech stacks with automatic stack detection, TDD enforcement, and tiered complexity management.

## Installation

```bash
# 1. Add marketplace
/plugin marketplace add picpal/claude-baton

# 2. Install plugin
/plugin install claude-baton@claude-baton
```

Or load locally for development:

```bash
claude --plugin-dir /path/to/claude-baton
```

## Quick Start

```bash
# Initialize in your project
/baton:init

# Start developing — just describe what you need
"Add user authentication with JWT"

# Check status anytime
/baton:status
```

## How It Works

### Automatic Stack Detection
claude-baton reads your build files (package.json, build.gradle, go.mod, etc.) to detect tech stacks. No manual configuration needed.

**Supported stacks:** TypeScript, React, React Native, Expo, Next.js, Java, Spring Boot, Kotlin, Python, Go, Rust, Swift

### Tiered Pipeline

| Tier | Score | Pipeline |
|------|-------|----------|
| 1 — Light | 0-3 pts | Analysis → Worker → QA → Done |
| 2 — Standard | 4-8 pts | Interview → Analysis → Planning → Tasks → Workers → QA → Review(3) → Done |
| 3 — Full | 9+ pts | Interview → Analysis → Planning(3) → Tasks → Workers → QA → Review(5) → Done |

### Complexity Scoring
| Criterion | Score |
|-----------|-------|
| Files to change (max 5) | 0–5 |
| Cross-service dependency | +3 |
| New feature | +2 |
| Architectural decisions | +3 |
| Security/auth/payment | +4 |
| DB schema change | +3 |

### Security First
- Automatic security pattern scanning (CRITICAL/HIGH/MEDIUM)
- Security Guardian with exclusive Rollback authority
- Safe-commit tags for reliable rollback points
- Security constraints auto-injected after incidents

### TDD Enforced
All workers follow strict TDD: test first, implement second, refactor third.

## Commands

| Command | Description |
|---------|-------------|
| `/baton:init` | Initialize pipeline in current project |
| `/baton:status` | Show pipeline status |
| `/baton:auto` | Toggle auto-mode on/off (default: on) |
| `/baton:issue` | Register an issue manually |
| `/baton:checkpoint` | Save, list, and restore named checkpoints |
| `/baton:rollback` | Security rollback to last safe tag |
| `/baton:tier` | Show/override current Tier |
| `/baton:{phase}` | Manually run a phase: interview, analyze, plan, tasks, work, qa, review |

## Pipeline Agents

| Agent | Role | Model |
|-------|------|-------|
| Main Orchestrator | Coordinates all phases | claude-opus-4-7 (effort: xhigh) |
| Interview Agent | Clarifies requirements | claude-sonnet-4-6 |
| Analysis Agent | Stack detection + impact analysis | claude-opus-4-7 |
| Planning (Security/Arch/Dev) | Tier 3 design | claude-opus-4-7 (effort: xhigh) |
| Task Manager | Task splitting + stack tagging | claude-opus-4-7 |
| Worker | TDD implementation | claude-opus-4-7 (isolation: worktree) |
| QA (Unit/Integration) | Test verification | claude-sonnet-4-6 |
| Security Guardian | Security review + Rollback | claude-opus-4-7 (effort: xhigh) |
| Quality Inspector | Code quality review | claude-sonnet-4-6 (memory: project) |
| TDD Enforcer (Reviewer) | TDD compliance review | claude-sonnet-4-6 (memory: project) |
| Performance Analyst | Performance review (Tier 3) | claude-sonnet-4-6 (memory: project) |
| Standards Keeper | Standards review (Tier 3) | claude-sonnet-4-6 (memory: project) |

## What's New in v1.11.0

- **Explicit model IDs** — Pipeline agents now use Claude 4.x model IDs (Opus 4.7, Sonnet 4.6, Haiku 4.5) instead of aliases.
- **Tier-aware effort levels** — Tier 3 planners and Security Guardian use `effort: xhigh` (Opus 4.7); reviewers use `effort: high`.
- **Worker isolation** — `worker-agent` runs in an isolated git worktree (`isolation: worktree`), strengthening scope-lock with auto-cleanup.
- **Review memory** — Review agents (Quality, TDD, Standards, Performance) accumulate codebase patterns via `memory: project`, complementing `lessons.md`.
- **Stack-aware skill activation** — `paths` glob patterns auto-activate the right `baton-tdd-*` skill based on file extension.
- **Hardened hook gating** — Main is blocked from direct read/grep/find on protected paths (`agents/`, `skills/`, `hooks/`, `src/`, etc.) — use Explore agent instead.
- **Hook event cleanup** — Removed 4 unofficial events that never fired; migrated to official `SessionStart` / `PreCompact`.

## Configuration

### Environment Variables
- `LOG_MODE`: minimal / execution (default) / verbose

## License

MIT
