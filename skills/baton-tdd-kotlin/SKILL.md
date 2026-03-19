---
name: baton-tdd-kotlin
description: |
  TDD rules and QA checklist for Kotlin projects.
  Extends baton-tdd-java with Kotlin-specific testing frameworks,
  security rules, and quality checks.
extends: baton-tdd-java
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Kotlin

## Additional Frameworks
- MockK (Kotlin-friendly alternative to Mockito)
- kotlinx-coroutines-test (Coroutine testing)

## Kotlin Specific Rules
- Maintain data class immutability
- Test all branches of sealed class
- suspend functions: test within runTest { } blocks
- Nullable handling: no !! operator usage → use let / ?:

## QA Checklist

### Kotlin Specific Verification
- [ ] No !! operator usage
- [ ] sealed class branch exhaustiveness confirmed
- [ ] Coroutine tests use runTest blocks
- [ ] data class immutability maintained
