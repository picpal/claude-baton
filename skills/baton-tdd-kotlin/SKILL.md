---
name: baton-tdd-kotlin
description: |
  TDD rules and QA checklist for Kotlin projects (suspend functions, data class, sealed class, coroutine, kotlinx).
  Uses MockK instead of Mockito, kotlinx-coroutines-test for coroutine testing, runTest blocks for suspend functions.
  Enforces no !! operator, sealed class exhaustiveness, and data class immutability.
  Trigger when: project has .kt source files, build.gradle.kts, or kotlin plugin in build configuration.
  Do NOT use for pure Java projects (use baton-tdd-java) or Spring Boot projects without Kotlin (use baton-tdd-spring-boot).
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
