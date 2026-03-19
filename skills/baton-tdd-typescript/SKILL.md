---
name: baton-tdd-typescript
description: |
  TDD rules and QA checklist for TypeScript projects.
  Extends baton-tdd-base with TypeScript-specific frameworks,
  security rules, and quality checks.
extends: baton-tdd-base
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — TypeScript

## Test Framework
- Jest or Vitest
- Type safety: ts-jest or Vitest built-in TypeScript support

## Test Execution
npm test
npm test -- --coverage

## Coverage
- Tool: istanbul (built into Jest) / v8 (Vitest)
- Threshold: Line coverage 80% or above

## TypeScript-Specific Rules
- No use of any type → use unknown or generics
- Secrets: process.env.KEY (no hardcoding)
- Null checks: use optional chaining (?.)

## scope-lock
If modifications outside assigned files are detected → report "SCOPE_EXCEED: {filename}" to Main and wait

## QA Checklist

### TypeScript-Specific Verification
- [ ] tsc --noEmit type check passes
- [ ] No use of any type
- [ ] strict mode enabled
- [ ] No unused imports/variables (noUnusedLocals)
