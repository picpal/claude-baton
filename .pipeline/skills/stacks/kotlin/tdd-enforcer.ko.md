# TDD Enforcer — Kotlin
# extends: stacks/java/tdd-enforcer.md

## 추가 프레임워크
- MockK (Mockito 대신 Kotlin 친화적)
- kotlinx-coroutines-test (Coroutine 테스트)

## Kotlin 전용 규칙
- data class 불변성 유지
- sealed class 모든 분기 테스트
- suspend 함수: runTest { } 블록에서 테스트
- nullable 처리: !! 연산자 사용 금지 → let / ?: 사용
