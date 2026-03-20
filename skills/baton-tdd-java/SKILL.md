---
name: baton-tdd-java
description: |
  TDD rules and QA checklist for pure Java projects (pure Java with no spring-boot/kotlin in build.gradle/pom.xml).
  Uses JUnit 5 + Mockito for testing, JaCoCo for coverage (80%+), PreparedStatement/JPA for SQL injection prevention.
  Trigger when: project has only .java files with no Spring Boot dependencies and no Kotlin source.
  Do NOT use for Spring Boot projects (use baton-tdd-spring-boot) or Kotlin projects (use baton-tdd-kotlin).
extends: baton-tdd-base
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Java

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

## QA Checklist

### Java-Specific Verification
- [ ] All JUnit 5 tests pass
- [ ] JaCoCo coverage 80% or above
- [ ] PreparedStatement / JPA usage confirmed (SQL Injection prevention)
- [ ] Bean Validation applied
