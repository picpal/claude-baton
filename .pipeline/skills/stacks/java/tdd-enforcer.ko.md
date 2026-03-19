# TDD Enforcer — Java
# extends: base/tdd-enforcer.md

## 테스트 프레임워크
- JUnit 5 + Mockito

## 테스트 실행
mvn test
./gradlew test

## 커버리지
- 도구: JaCoCo
- 기준: 라인 커버리지 80% 이상
- 확인: build/reports/jacoco/index.html

## Java 전용 보안 규칙
- SQL: PreparedStatement 또는 JPA 사용 (String 직접 조합 금지)
- 시크릿: 환경변수 또는 Vault (하드코딩 금지)
- 입력값: Bean Validation (@NotNull, @Size 등)

## scope-lock
할당 파일 외 수정 발견 시 → "SCOPE_EXCEED: {파일명}" Main 보고 후 대기
