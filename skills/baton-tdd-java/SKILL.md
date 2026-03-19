---
name: baton-tdd-java
description: |
  TDD rules and QA checklist for Java projects.
  Extends baton-tdd-base with Java-specific frameworks,
  security rules, and quality checks.
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
