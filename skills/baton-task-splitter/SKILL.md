---
name: baton-task-splitter
description: |
  Use this skill whenever the user wants to split work into tasks, create a task list from a plan,
  or break a project into smaller pieces. Handles requests like "분리해줘", "나눠줘", "쪼개줘",
  "작성해줘" related to tasks/작업/태스크/할일/todo, and English equivalents like "decompose into
  work items", "break down the plan", "create tasks". Reads plan.md or complexity-score.md,
  produces structured todo.md with stack tags and dependency tracking.
  NOT for checking status, viewing progress, reviewing code, or reading existing todos.
allowed-tools: Read, Write, Bash, Grep, TaskCreate, TaskList
---

# Task Splitter Skill

## Role
Break plans into independent, testable task units. Auto-tag each task with its stack.

## Task Separation Principles
- One task = one responsibility
- Smallest unit that can be unit tested independently
- File scope must be explicitly defined per task
- If a task spans two or more stacks, split it (see `references/multi-stack-rules.md`)

## Stack Auto-Tagging Method
1. Read "File -> Stack Mapping" from `complexity-score.md`
2. Match task file paths against mapping rules
3. Use `scripts/tag-stack.sh <filepath>` for unmapped files
4. Record stack skill path in the task entry
5. If still uncertain, report to Main and wait

## todo.md Output Format
```
- [ ] task-01: {description}
      assignee: Worker-A | model: opus
      stack: spring-boot
      skill: .pipeline/skills/stacks/spring-boot/tdd-enforcer.md
      files: [AuthService.java, AuthController.java]
      depends: (none or task-id)
```

## Built-in Task Registration
Each task is registered via `TaskCreate` at the same time todo.md is written.

### TaskCreate Invocation Rules
- description: use the format "task-{id}: {description}"
- status: "todo" (initial value)
- metadata must include stack, skill, model, files, and depends
- After all tasks are registered, verify with `TaskList`

### Dependency Mapping
- `depends: task-{id}` in todo.md is recorded identically in TaskCreate's metadata.depends
- If a circular dependency is detected, report to Main and wait

## GitHub Issue Checklist Sync
After all tasks are written to todo.md and registered via TaskCreate:

1. Check if `.baton/issue.md` exists and has an issue number
2. If yes, read the current issue body: `gh issue view <number> --json body -q .body`
3. Build a task checklist block:
   ```markdown
   ## Tasks
   - [ ] task-01: {description} (`{stack}`)
   - [ ] task-02: {description} (`{stack}`)
   ```
4. Append the checklist to the existing issue body:
   ```bash
   gh issue edit <number> --body "$EXISTING_BODY

   ## Tasks
   $CHECKLIST"
   ```
5. If `gh` CLI is unavailable or fails, skip gracefully (non-blocking)
