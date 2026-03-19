# claude-baton

Multi-agent development pipeline plugin for Claude Code.

Orchestrates the full development lifecycle — from requirements interview to security review — across 12 tech stacks with automatic stack detection, TDD enforcement, and tiered complexity management.

## Installation

```bash
# Install from GitHub
claude plugin install github:claude-baton/claude-baton
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
| `/baton:rollback` | Security rollback to last safe tag |
| `/baton:tier` | Show/override current Tier |

## Pipeline Agents

| Agent | Role | Model |
|-------|------|-------|
| Main Orchestrator | Coordinates all phases | opus |
| Interview Agent | Clarifies requirements | sonnet |
| Analysis Agent | Stack detection + impact analysis | opus |
| Planning (Security/Arch/Dev) | Tier 3 design | opus |
| Task Manager | Task splitting + stack tagging | opus |
| Worker | TDD implementation | auto |
| QA (Unit/Integration) | Test verification | sonnet |
| Security Guardian | Security review + Rollback | opus |
| Quality Inspector | Code quality review | sonnet |
| TDD Enforcer (Reviewer) | TDD compliance review | sonnet |
| Performance Analyst | Performance review (Tier 3) | sonnet |
| Standards Keeper | Standards review (Tier 3) | sonnet |

## Configuration

### Environment Variables
- `LOG_MODE`: minimal / execution (default) / verbose

### Options (pass with any request)
- `--ask-mode on/off` — Force confirmation before each phase
- `--log-mode minimal/execution/verbose` — Set logging level
- `--tier 1/2/3` — Force tier (for testing)

## License

MIT
