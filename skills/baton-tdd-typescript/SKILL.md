---
name: baton-tdd-typescript
description: |
  TDD skill for pure TypeScript projects — package.json에 react/next/expo 없는 순수 TS 프로젝트 전용.
  Jest/Vitest + ts-jest, strict mode, no-any rule 적용.
  NOT for React/Next.js/Expo/React Native projects — use the corresponding sister skill instead.
  Triggers when: tsconfig.json exists AND package.json has NO react, next, or expo dependency.
  Extends baton-tdd-base with TypeScript-specific frameworks, security rules, and quality checks.
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
