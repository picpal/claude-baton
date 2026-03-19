# TDD Enforcer — Java
# extends: base/tdd-enforcer.md

## Test Framework
- JUnit 5 + Mockito

## Test Execution
mvn test
./gradlew test

## Coverage
- Tool: JaCoCo
- Threshold: Line coverage 80% or above
- Report: build/reports/jacoco/index.html

## Java-Specific Security Rules
- SQL: use PreparedStatement or JPA (no direct String concatenation)
- Secrets: environment variables or Vault (no hardcoding)
- Input validation: Bean Validation (@NotNull, @Size, etc.)

## scope-lock
If modifications outside assigned files are detected → report "SCOPE_EXCEED: {filename}" to Main and wait
