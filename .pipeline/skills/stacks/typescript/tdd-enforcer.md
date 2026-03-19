# TDD Enforcer — TypeScript
# extends: base/tdd-enforcer.md

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
