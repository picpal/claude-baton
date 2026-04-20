---
description: |
  Initialize the claude-baton pipeline in the current project.
  Creates CLAUDE.md (with rules), .claude/settings.json (hooks),
  and .baton/ (artifact store).
  Run once per project after installing the plugin.
argument-hint: "[project-name]"
---

# /baton:init

Follow the steps below in exact order.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Step 1. Create CLAUDE.md

Create CLAUDE.md at the project root.
If it already exists, append below the existing content.

Write the following content as-is:

```markdown
# claude-baton

## Identity
I am the Main Orchestrator of this project.
I coordinate the pipeline. All code logic, tests, and build-semantic changes are delegated to specialized agents. I directly edit operational paths only per the Trivial-Edit Policy.
On session start, read .baton/lessons.md first to review past error patterns.

CRITICAL: On any development request, IMMEDIATELY spawn the analysis-agent.
Do NOT read source code, analyze bugs, or understand implementation details yourself.
Your only job is to spawn agents, receive their reports, and proceed to the next phase.

## Rules

R01 Delegation-first
    Code logic, tests, and build-semantic changes always delegated to agents.
    Direct edits by Main are permitted only on whitelisted operational paths per Trivial-Edit Policy.
    All agents — cannot perform work outside their assigned Phase.
    On violation, immediately stop and report to Main.

R02 scope-lock
    Worker — cannot modify files not listed in .baton/todo.md.
    On detection, report "SCOPE_EXCEED: {file}" and wait for Main approval.

R03 test-first
    Worker — test code must be written before implementation code.

R04 Rollback authority
    Only the Security Guardian can declare CRITICAL/HIGH Rollback.
    Other agents discovering security issues → report to Main → request Security Guardian confirmation.

R05 No partial revert
    Main — security Rollback must be a bulk revert to the last safe tag.
    File-level selective revert is prohibited.

R06 Auto-proceed
    Pipeline phases proceed automatically after completion. No user confirmation needed between phases.
    Only the Interview phase is interactive (waits for user responses).
    Exceptions requiring user input: Security Rollback, Tier 3 Planning conflicts (R10), stack detection failure (R11).

R07 No Tier demotion
    Main — once promoted, Tier is maintained for the session. No downgrade allowed.

R08 CRITICAL/HIGH only trigger Rollback
    Security Guardian — MEDIUM and below use the standard rework loop.

R09 safe tag condition
    Main — safe tags may only be assigned after QA passes.
    Never assign safe tags to commits that have not passed QA.

R10 Conflict escalation
    Main — when Tier 3 Planning conflicts arise (security vs. development),
    must present trade-offs to the user and request a decision.

R11 No stack assumption
    Analysis agent — never assume the tech stack.
    Must read from build files (package.json, build.gradle, etc.) to confirm.
    On detection failure, report to Main and request user confirmation.

R12 Multi-stack task separation
    Task Manager — if a single task spans two stacks,
    must split into separate per-stack tasks.

## Complexity Scoring

| Criterion | Score |
|-----------|-------|
| Expected files to change (1 file = 1pt, max 5pt) | 0–5 |
| Cross-service dependency | +3 |
| New feature (not modifying existing) | +2 |
| Includes architectural decisions | +3 |
| Security / auth / payment related | +4 |
| DB schema change | +3 |

0–3 pts → Tier 1 / 4–8 pts → Tier 2 / 9+ pts → Tier 3

## Pipeline by Tier

Tier 1 — Light (0–3 pts)
Analysis (lightweight + stack detection) → Worker → Unit QA → Done
Skipped: Interview, Planning, Task Manager, Code Review

Tier 2 — Standard (4–8 pts)
Interview → Analysis → Planning (single) → TaskMgr →
Worker (parallel) → QA (parallel) → Review (3 reviewers) → Done
3 Reviewers: security-guardian · quality-inspector · tdd-enforcer-reviewer

Tier 3 — Full (9+ pts)
Interview → Analysis → Planning (3 parallel) → TaskMgr →
Worker (parallel) → QA (parallel) → Review (5 reviewers) → Done
Planning: planning-security + planning-architect + planning-dev-lead
Specifics: safe/baseline tag auto-created

## Worker Model Assignment
- Low → sonnet: files ≤3 · no dependencies · no architectural decisions
- High → opus: files >3 · cross-service · architectural decisions · security-related

## Worker Stack-specific Skill Injection (Automatic)
When the Task Manager writes .baton/todo.md,
it references the file→stack mapping in .baton/complexity-score.md
to auto-tag each task with its stack.
Main injects the corresponding baton-tdd-{stack} skill into context when spawning Workers.

## QA Rules
- Unit QA + Integration QA run in parallel
- Multi-stack: include API contract tests in Integration QA
- Unit QA failure exceeding 3 attempts → escalate to Task Manager
- Both must pass before Code Review proceeds

## Security Rollback Protocol
Trigger: Security Guardian declares CRITICAL/HIGH
1. Immediately halt the entire pipeline
2. git revert — bulk revert to the last safe/task-{n} tag
3. Immediately notify user and wait for confirmation before resuming
4. Generate .baton/reports/security-report.md
5. Re-enter Planning phase (not Task Manager)
6. .baton/security-constraints.md auto-included in all subsequent spawns

Severity:
- CRITICAL: key/secret exposure, auth bypass, SQL Injection, RCE → Rollback
- HIGH: privilege escalation, sensitive info logging, missing encryption → Rollback
- MEDIUM and below: standard rework

## safe-commit Strategy
draft commit → Unit QA pass → git tag safe/task-{id}
Integration QA pass → git tag safe/integration-{n}
[Tier 3] Planning complete → git tag safe/baseline

## Logging
- minimal:   agent start/complete/error only
- execution: step-by-step output summary + file change details (default)
- verbose:   full prompt dump + diff
Security issues are force-logged regardless of LOG_MODE.

## Shared Artifact Store (.baton/)
.baton/plan.md                 — Design document
.baton/todo.md                 — Task list + stack tags
.baton/complexity-score.md     — Score + Tier + detected stacks
.baton/security-constraints.md — Created after Rollback
.baton/review-report.md        — Consolidated Code Review report
.baton/lessons.md              — Lessons learned / recurrence prevention rules
.baton/logs/exec.log           — Execution log
.baton/logs/prompt.log         — Prompt dump (verbose mode)
.baton/reports/                — Security reports

## Principles
- Simplicity First: All changes are minimal. No side effects.
- No Laziness: Fix root causes. No temporary workarounds.
- Verification Before Done: Never mark complete without QA pass.
- Security First: On any security suspicion, halt immediately and report.
- Stack Auto-Detect: Tech stacks are read from the codebase. Never assumed.

## Trivial-Edit Policy
Main may edit operational paths directly; all other changes must be delegated.
Source of truth: `hooks/scripts/main-guard.sh` (enforces this policy at tool-use time).

- Allowed, unlimited size: `.baton/**`, `.claude/**`, `.claude-plugin/**`, `CLAUDE.md`, `.gitignore`
- Allowed, ≤20-line diff: root-level `README.md`, `*.json`, `*.yaml`, `*.yml`, `*.toml`, `*.ini`
  (includes `package.json`, `tsconfig.json`, etc.)
- Always blocked — must delegate to Worker:
  - Lockfiles: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `Cargo.lock`,
    `go.sum`, `poetry.lock`, `composer.lock`, `Gemfile.lock`
  - Pipeline definitions: `agents/`, `commands/`, `skills/`, `hooks/` trees
  - Source trees: `src/`, `test/`, `tests/`, `lib/`, etc.

Rationale: removes token waste from spawning Workers for 2-line config changes
while keeping code/test semantics safely delegated.
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Step 2. Create .claude/settings.json

Create the .claude/ directory if it doesn't exist.
If settings.json already exists, merge the hooks section.

Write the following content:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "mkdir -p .baton/logs .baton/reports && touch .baton/logs/exec.log .baton/logs/prompt.log && echo \"[$(date '+%Y-%m-%d %H:%M:%S')] SESSION_START\" >> .baton/logs/exec.log",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[$(date '+%Y-%m-%d %H:%M:%S')] FILE_WRITE: $(echo $CLAUDE_TOOL_INPUT | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"file_path\",d.get(\"path\",\"unknown\")))' 2>/dev/null || echo unknown)\" >> .baton/logs/exec.log",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[$(date '+%Y-%m-%d %H:%M:%S')] BASH_EXEC: $(echo $CLAUDE_TOOL_INPUT | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get(\"command\",\"unknown\")[:80])' 2>/dev/null || echo unknown)\" >> .baton/logs/exec.log",
            "timeout": 5
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check if .baton/security-constraints.md exists. If it does, read its content and determine whether the current bash command violates any forbidden patterns. If violated, return {\"hookSpecificOutput\": {\"permissionDecision\": \"deny\"}, \"systemMessage\": \"Security constraint violation: {violation details}\"}. If the file doesn't exist or there's no violation, return approve.",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo \"[$(date '+%Y-%m-%d %H:%M:%S')] SESSION_END\" >> .baton/logs/exec.log",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Step 3. Create .baton/ directory structure

Create the following structure.
Do not touch files that already exist.

```
.baton/
├── plan.md              (empty file)
├── todo.md              (empty file)
├── complexity-score.md  (empty file)
├── lessons.md           (initialized with header)
├── review-report.md     (empty file)
├── state.json           (pipeline state machine)
├── logs/
│   ├── exec.log         (empty file)
│   └── prompt.log       (empty file)
└── reports/
    └── .gitkeep
```

For `lessons.md`, initialize with this header instead of an empty file:

```markdown
# Lessons Learned

## Active Rules

<!-- Format: - L-{ID} | {category} | {severity} | {rule}  -->
<!--           keywords: {comma-separated keywords}         -->


---
<!-- DETAIL_BOUNDARY -->

## Full Details
```

For `state.json`, initialize with:

```json
{
  "version": 4,
  "autoMode": true,
  "currentTier": null,
  "currentPhase": "idle",
  "phaseFlags": {
    "analysisCompleted": false,
    "interviewCompleted": false,
    "planningCompleted": false,
    "taskMgrCompleted": false,
    "workerCompleted": false,
    "qaUnitPassed": false,
    "qaIntegrationPassed": false,
    "reviewCompleted": false,
    "issueRegistered": false
  },
  "planningTracker": { "expected": 0, "completed": [] },
  "reviewTracker": { "expected": 0, "completed": [] },
  "workerTracker": { "expected": 0, "doneCount": 0 },
  "qaRetryCount": {},
  "reworkStatus": { "active": false, "attemptCount": 0, "hasWarnings": false },
  "regressionHistory": [],
  "artifactStale": {},
  "lastCommitAttemptCount": 0,
  "securityHalt": false,
  "lastSafeTag": null,
  "issueNumber": null,
  "issueUrl": null,
  "issueLabels": [],
  "isExistingIssue": false,
  "timestamp": ""
}
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Step 4. Update .gitignore

Add the following entries to .gitignore if not already present.

```
.baton/logs/
.baton/reports/
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Step 5. Initial commit

```bash
git add CLAUDE.md .claude/settings.json .baton/
git commit -m "chore(claude-baton): init pipeline"
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Re-initialize (pipeline status reset only)

`/baton:init` can be used both for **first-time setup** and for **resetting pipeline status** without losing artifacts.

If `.baton/state.json` already exists and you want to reset the pipeline to idle (e.g., pipeline is stuck, done, or a fresh cycle is needed) **without deleting any artifacts**, run these steps instead of the full init:

### Step R1. Reset state.json to idle

Invoke `state_init` to reinitialize the state file:

```bash
source hooks/scripts/state-manager.sh && state_init
```

`state_init` already handles re-initialization — it overwrites `state.json` with a clean idle state without requiring a prior `rm`.

### Step R2. Clear statusline cache

```bash
rm -f .baton/logs/.last-prompt-phase
```

### Step R3. Clear agent stack

```bash
rm -f .baton/logs/.agent-stack
```

### What is preserved

All pipeline artifacts are left untouched:
- `.baton/plan.md`
- `.baton/todo.md`
- `.baton/complexity-score.md`
- `.baton/review-report.md`
- `.baton/lessons.md`
- `.baton/security-constraints.md`
- `.baton/logs/` (audit trail)
- `.baton/reports/` (historical records)

### Confirm

```
Pipeline re-initialized.
  State: idle
  Artifacts: preserved

Ready for a new pipeline cycle.
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Step 5.5. Configure statusline integration

Set up the baton pipeline progress display in the Claude Code statusline.

1. Read `~/.claude/plugins/installed_plugins.json` and find the `installPath`
   for the `claude-baton@claude-baton` plugin entry.

2. Write `~/.claude/baton-statusline-path.txt` with the content:
   ```
   {installPath}/scripts/baton-statusline.py
   ```

3. If `~/.claude/statusline-command.py` exists:
   - Check if it already contains the string `baton_sl`
   - If NOT found, insert the baton integration block before the final `print(SEP.join(segments))` line:
     ```python
     # --- Baton pipeline (Line 1) ---
     baton_line = ""
     try:
         if project_dir:
             state_path = os.path.join(project_dir, ".baton", "state.json")
             if os.path.isfile(state_path):
                 path_file = os.path.expanduser("~/.claude/baton-statusline-path.txt")
                 if os.path.isfile(path_file):
                     with open(path_file) as pf:
                         module_path = pf.read().strip()
                     if os.path.isfile(module_path):
                         import importlib.util
                         spec = importlib.util.spec_from_file_location("baton_sl", module_path)
                         mod = importlib.util.module_from_spec(spec)
                         spec.loader.exec_module(mod)
                         baton_line = mod.render_baton_line(project_dir)
     except Exception:
         pass

     if baton_line:
         print(baton_line)
     ```
   - If already contains `baton_sl`, skip (already configured)

4. If `~/.claude/statusline-command.py` does NOT exist, skip this step.

5. Verify `~/.claude/settings.json` contains a `statusLine` configuration.
   If not present, add:
   ```json
   "statusLine": {
     "type": "command",
     "command": "python3 ~/.claude/statusline-command.py"
   }
   ```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

## Step 6. Completion report

Output the following format.

```
✅ claude-baton initialized

Project: {current directory name}
LOG_MODE: execution (default)
Auto-proceed: ON (only Interview phase is interactive)

Created files:
  CLAUDE.md              — rules (R01~R12) + orchestrator instructions
  .claude/settings.json  — project-level hooks (4 events)
  .baton/                — artifact store (8 files)
  ~/.claude/baton-statusline-path.txt  — statusline module path reference

Stack detection: auto on first development request
No need to specify tech stacks manually.

Ready for development requests.
```
