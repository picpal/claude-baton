---
name: baton:init
description: Initialize claude-baton pipeline in the current project.
---

# /baton:init

Initialize the claude-baton pipeline infrastructure.

## Steps
1. Create .baton/ directory structure:
   - .baton/logs/
   - .baton/reports/
   - .baton/plan.md
   - .baton/todo.md
   - .baton/complexity-score.md
   - .baton/lessons.md
2. Add .baton/logs/ and .baton/reports/ to .gitignore
3. Initialize exec.log with session start timestamp
4. Check for existing .baton/lessons.md and load if present

## Output
```
✅ claude-baton initialized

Project: {PROJECT_NAME}
LOG_MODE: execution (default)
Ask Mode: OFF (default)

Stack detection: auto on first development request
  (based on package.json / build.gradle / go.mod etc.)

Ready for development requests.

Options:
  --ask-mode on/off
  --log-mode minimal/execution/verbose
  --tier 1/2/3 (force tier, for testing)
```
