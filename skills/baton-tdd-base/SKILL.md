---
name: baton-tdd-base
description: |
  모든 언어에 공통 적용되는 TDD 기본 원칙. RED-GREEN-REFACTOR 사이클 강제.
  Use this skill when: 특정 언어에 국한되지 않는 일반 TDD 원칙이 필요할 때.
  Trigger: "TDD 원칙", "테스트 먼저", "RED-GREEN-REFACTOR", "TDD principles", "test-first".
  This is the BASE skill — all language-specific TDD skills (Python/Go/Rust/Swift) extend this.
  For language-specific rules, use baton-tdd-{lang} instead (they auto-include this base).
  Test code must be written before implementation code. Enforces scope-lock rules.
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
