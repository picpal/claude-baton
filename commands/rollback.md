---
name: baton:rollback
description: Execute security rollback to the last safe tag.
---

# /baton:rollback

Execute a security rollback to the last safe tag.

## Prerequisites
- Must have at least one safe/* tag
- Should only be triggered by Security Guardian CRITICAL/HIGH finding
  or manually by user
- `securityHalt=true` must already be set in state.json (done automatically
  by security-halt.sh in step 1 below)

## Full Rollback Sequence

### Step 1 — Security Halt (automated, via security-halt.sh)

`security-halt.sh` is invoked by the Security Guardian agent when a CRITICAL
or HIGH finding is declared. It performs the following state.json operations:

```bash
state_write "securityHalt" "true"
state_write "securityHaltContext.severity" "<CRITICAL|HIGH>"
state_write "securityHaltContext.finding" "<brief description>"
state_write "securityHaltContext.sourceAgent" "<agent name>"
state_write "securityHaltContext.timestamp" "<ISO-8601>"
```

This flags the pipeline so that:
- `regress_to_phase()` refuses to execute while halt is active (SC-REGRESS-03)
- `phase-gate.sh` refuses to advance any phase

A security report placeholder is written to `.baton/reports/security-report.md`.

> **Who runs this:** The Security Guardian agent invokes `security-halt.sh`
> automatically. Main does NOT need to trigger this manually.

---

### Step 2 — Git Revert to lastSafeTag

```bash
SAFE_TAG=$(git tag -l 'safe/*' --sort=-version:refname | head -1)
SAFE_HASH=$(git rev-parse "$SAFE_TAG")
git revert "$SAFE_HASH"..HEAD --no-commit
git commit -m "revert: security rollback to $SAFE_TAG"
```

> **Who runs this:** Main Orchestrator or user runs this manually.
> Do not skip — the revert must happen before clearing the halt.

---

### Step 3 — Generate Security Report and Lessons

1. Fill in `.baton/reports/security-report.md` with the full finding analysis.
2. Update `.baton/security-constraints.md` with the new constraint.
3. Append a lesson entry to `.baton/lessons.md` in BOTH sections:
   - Append one-liner before DETAIL_BOUNDARY (Active Rules section):
   ```markdown
   - L-{YYYY-MM-DD}-{seq} | security | critical | {imperative prevention rule derived from the finding}
     keywords: {comma-separated keywords derived from the finding}
   ```
   - Append full entry after DETAIL_BOUNDARY (Full Details section):
   ```markdown
   ---
   ### L-{YYYY-MM-DD}-{seq} | security | critical
   - **trigger**: security-rollback
   - **task**: {task-id or "session-level"}
   - **what happened**: Security Rollback triggered — {CRITICAL or HIGH}: {brief description of finding}
   - **root cause**: {from security-report.md analysis}
   - **rule**: {imperative prevention rule derived from the finding}
   - **files**: {files that contained the vulnerability}
   ```

> **Who runs this:** Main Orchestrator fills these documents based on the
> Security Guardian's finding report.

---

### Step 4 — Wait for User Confirmation

Notify the user and display:
- The safe tag rolled back to
- The security finding summary
- The prevention rule recorded in lessons.md

Do NOT proceed to step 5 until the user explicitly confirms the rollback
is clean and they are ready to resume the pipeline.

---

### Step 5 — Clear the Security Halt

After user confirmation, Main clears the halt flag in state.json:

```bash
# Source the state manager to access state_write
source hooks/scripts/find-baton-root.sh
source hooks/scripts/state-manager.sh

state_write "securityHalt" "false"
```

This unblocks `regress_to_phase()` (SC-REGRESS-03 guard lifted) so the
pipeline can advance again.

> **Who runs this:** Main Orchestrator executes this after user confirms.

---

### Step 6 — Deep Regression to Planning (--force required)

Main calls `regress_to_phase` with the `--force` flag to reset the pipeline
back to the planning phase:

```bash
source hooks/scripts/regress-to-phase.sh

regress_to_phase "planning" "Security rollback: <reason>" --force
```

**Why `--force` is required:**

`regress_to_phase()` enforces SC-REGRESS-04: any regression spanning more
than one phase depth (review → planning is depth 4) is a "deep regression"
and is refused without `--force`. This guard exists to prevent accidental
wide-scope regressions during normal rework cycles. Security rollbacks are
an intentional deep regression, so `--force` is the explicit acknowledgment.

**What `--force` does:**

Bypasses the SC-REGRESS-04 depth check and executes the full atomic
regression, which:
- Resets `phaseFlags` for planning, taskmgr, worker, qa, and review to `false`
- Resets `planningTracker`, `workerTracker`, and `reviewTracker`
- Sets `reworkStatus.active = true` and increments `attemptCount`
- Marks `.baton/plan.md` and `.baton/todo.md` as stale in `artifactStale`
- Appends an entry to `regressionHistory`
- Sets `currentPhase = "planning"`

**SC-REGRESS-03 and SC-REGRESS-04 interaction:**

| Guard | Code | When active | Effect |
|-------|------|-------------|--------|
| SC-REGRESS-03 | exit 3 | `securityHalt=true` | Refuses all regression until halt cleared |
| SC-REGRESS-04 | exit 5 | depth > 1 without `--force` | Refuses deep regression; records `regressionPending` |

Both guards must be satisfied for regression to proceed. Clearing the halt
(step 5) satisfies SC-REGRESS-03; `--force` satisfies SC-REGRESS-04.

> **Who runs this:** Main Orchestrator executes this after clearing the halt.

---

### Step 7 — Re-spawn Planning Agents

With `currentPhase = "planning"` and all downstream flags reset, Main
re-spawns the Planning agents as in a normal pipeline run:

- Tier 2: 1 planner agent
- Tier 3: 3 planner agents (Security Architect, System Architect, Dev Lead)

The Security Architect must prioritize addressing the vulnerability pattern
identified in the security finding when creating the new plan.

> **Who runs this:** Main Orchestrator initiates the planning phase normally.

---

## State.json Summary

| State Field | After Step 1 | After Step 5 | After Step 6 |
|-------------|-------------|-------------|-------------|
| `securityHalt` | `true` | `false` | `false` |
| `securityHaltContext.*` | populated | populated | populated |
| `currentPhase` | unchanged | unchanged | `"planning"` |
| `phaseFlags.planningCompleted` | unchanged | unchanged | `false` |
| `phaseFlags.reviewCompleted` | unchanged | unchanged | `false` |
| `reworkStatus.active` | unchanged | unchanged | `true` |
| `artifactStale.plan.md` | unchanged | unchanged | `true` |

---

## Strictly Prohibited
- Selective per-file revert
- Revert to arbitrary commit without safe tag
- Calling `regress_to_phase` while `securityHalt=true` (SC-REGRESS-03 will refuse, exit 3)
- Calling `regress_to_phase` for a deep regression without `--force` (SC-REGRESS-04 will refuse, exit 5)
- Clearing the halt before the git revert is committed
- Resuming pipeline without user confirmation (step 4)
