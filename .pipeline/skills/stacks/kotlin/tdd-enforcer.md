# TDD Enforcer — Kotlin
# extends: stacks/java/tdd-enforcer.md

## Additional Frameworks
- MockK (Kotlin-friendly alternative to Mockito)
- kotlinx-coroutines-test (Coroutine testing)

## Kotlin Specific Rules
- Maintain data class immutability
- Test all branches of sealed class
- suspend functions: test within runTest { } blocks
- Nullable handling: no !! operator usage → use let / ?:
