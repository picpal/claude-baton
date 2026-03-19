---
name: baton-tdd-spring-boot
description: |
  TDD rules and QA checklist for Spring Boot projects.
  Extends baton-tdd-java with Spring Boot-specific testing frameworks,
  security rules, and quality checks.
extends: baton-tdd-java
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Spring Boot

## Additional Frameworks
- MockMvc (Spring MVC testing)
- @SpringBootTest + TestRestTemplate (integration testing)
- @DataJpaTest (repository testing)

## Spring Boot Specific Rules
- Use test slices: @WebMvcTest, @DataJpaTest
- Security configuration: use @WithMockUser
- Environment variables: separate into application-test.yml

## Running Tests
./gradlew test
./gradlew test jacocoTestReport

## QA Checklist

### Spring Boot Specific Verification
- [ ] @SpringBootTest integration tests passing
- [ ] MockMvc controller tests exist
- [ ] application-test.yml separation confirmed
- [ ] Security configuration tests exist
