---
name: baton:status
description: Show current pipeline status.
---

# /baton:status

Display the current state of the claude-baton pipeline.

## Information Displayed
- Current Tier level
- Active phase
- Task progress (from .baton/todo.md)
- Detected stacks (from .baton/complexity-score.md)
- QA status
- safe tags (git tag -l 'safe/*')
- LOG_MODE setting
- Any active security constraints

## Format
```
📊 claude-baton Status
━━━━━━━━━━━━━━━━━━━━
Tier:     {1|2|3}
Phase:    {current phase}
Stacks:   {detected stacks}
LOG_MODE: {minimal|execution|verbose}
Auto-proceed: ON (Interview phase is the only interactive phase)

Tasks:
  ✅ task-01: {description}
  🔄 task-02: {description} (in progress)
  ⬜ task-03: {description}

Safe Tags:
  safe/task-01  (abc1234)
  safe/task-02  (def5678)

Security: {No active constraints | ⚠️ security-constraints.md active}
```
