---
name: baton-task-splitter
description: |
  Breaks plans into independent tasks and identifies dependencies.
  Auto-tags each task with its stack from complexity-score.md.
  Splits multi-stack tasks into separate per-stack tasks.
allowed-tools: Read, Write
---

# Task Splitter Skill

## Role
Break plans into independent task units and identify dependencies.
Read the stack mapping from complexity-score.md to automatically tag each task with its stack.
There is no need for a human to specify the stack.

## Task Separation Principles
- One task = one responsibility
- Split into the smallest units that can be unit tested
- File scope must be clearly defined

## Stack Auto-Tagging Method
1. Read the "File → Stack Mapping" section of complexity-score.md
2. Match each task's file paths against the mapping rules
3. Record the corresponding stacks/ folder skill path in the task
4. If mapping is uncertain → report to Main and confirm

## Multi-Stack Task Handling
If a single task spans two stacks → task separation is mandatory
e.g.) "Login API integration" → task-A: Java API implementation / task-B: RN fetch implementation

## todo.md Format
```
- [ ] task-01: {description}
      assignee: Worker-A | model: opus
      stack: spring-boot
      skill: .pipeline/skills/stacks/spring-boot/tdd-enforcer.md
      files: [AuthService.java, AuthController.java]

- [ ] task-02: {description}
      assignee: Worker-B | model: sonnet
      stack: expo
      skill: .pipeline/skills/stacks/expo/tdd-enforcer.md
      files: [LoginScreen.tsx, useAuth.ts]
      depends: task-01
```
