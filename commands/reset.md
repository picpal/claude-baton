---
name: baton:reset
description: Reset pipeline state to idle. Use when pipeline is stuck or done and a fresh cycle is needed.
---

# /baton:reset

Reset the claude-baton pipeline state for a fresh cycle.

## When to Use
- Pipeline is in `done` state and a new task needs to start
- Pipeline is stuck (agent crashed, state inconsistent)
- User wants to abandon current pipeline and start over

## Behavior

### Step 1. Reset state.json
Delete and reinitialize `.baton/state.json` to idle state:

```bash
rm -f .baton/state.json
```

Then invoke `state_init` by running:

```bash
source hooks/scripts/state-manager.sh && state_init
```

If the hook script is unavailable, write the default state directly:

```json
{
  "version": 2,
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
  "reworkStatus": { "active": false, "attemptCount": 0 },
  "securityHalt": false,
  "lastSafeTag": null,
  "issueNumber": null,
  "issueUrl": null,
  "issueLabels": [],
  "isExistingIssue": false,
  "timestamp": ""
}
```

### Step 2. Clean agent stack
Remove stale agent tracking file:

```bash
rm -f .baton/logs/.agent-stack
```

### Step 3. Archive artifacts (optional)
If previous pipeline artifacts exist, ask the user:

> Previous pipeline artifacts found (plan.md, todo.md, complexity-score.md).
> Delete them for a clean start? (Y/n)

If yes:
```bash
rm -f .baton/plan.md .baton/todo.md .baton/complexity-score.md .baton/review-report.md
```

Always preserve:
- `.baton/lessons.md` (cross-session learning)
- `.baton/logs/` (audit trail)
- `.baton/reports/` (historical records)
- `.baton/security-constraints.md` (safety rules)

### Step 4. Confirm

```
Pipeline reset complete.
  State: idle
  Tier: (not determined)
  Artifacts: {cleaned | preserved}

Ready for a new pipeline cycle.
```
