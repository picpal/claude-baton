---
name: baton:status-reset
description: Reset pipeline status to idle. Clears state.json and statusline cache only — artifacts (plan.md, todo.md, etc.) are preserved.
---

# /baton:status-reset

Reset the pipeline state to idle without touching any artifacts.

## Steps

### Step 1. Re-initialize state.json

```bash
bash -c 'SCRIPT_DIR="$(pwd)/hooks/scripts"; source "$SCRIPT_DIR/find-baton-root.sh"; source "$SCRIPT_DIR/state-manager.sh"; rm -f "$STATE_FILE"; state_init'
```

### Step 2. Clear statusline cache and agent stack

```bash
rm -f .baton/logs/.last-prompt-phase .baton/logs/.agent-stack
```

## Confirmation

Output exactly:

```
Pipeline status reset to idle.
  State: idle | Tier: — | Artifacts: preserved
```
