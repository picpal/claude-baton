---
name: baton-tdd-base
description: |
  Base TDD principles applied to all Workers.
  Test code must be written before implementation code.
  Enforces scope-lock rules.
allowed-tools: Read, Write, Bash
---

# TDD Enforcer Skill (Base)

## Absolute Principle: Test Code → Implementation Code Order

## TDD Cycle
1. RED      — Write a failing test
2. GREEN    — Minimal implementation to pass the test
3. REFACTOR — Clean up code (tests continue to pass)

## Test Writing Standards
- Unit tests per function/method
- Normal cases + edge cases + failure cases
- Test names: "should ..." format

## scope-lock Rules
When modification is detected outside assigned files:
1. Immediately stop work
2. Report "SCOPE_EXCEED: {filename}" to Main
3. Wait for Main's approval

## Commit Message Format
feat(task-{id}): {one-line summary}
test(task-{id}): {test description}
fix(task-{id}):  {fix description}
