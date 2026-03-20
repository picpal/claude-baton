---
name: baton-tdd-spring-boot
description: |
  TDD rules and QA checklist for Spring Boot applications (SpringApplication, spring-boot-starter-* dependencies).
  Uses MockMvc, @SpringBootTest, @WebMvcTest, @DataJpaTest, application-test.yml, @WithMockUser for testing.
  Trigger when: project contains spring-boot-starter dependencies, SpringApplication class, or Spring Boot auto-configuration.
  Do NOT use for pure Java projects without Spring Boot (use baton-tdd-java) or Kotlin-only projects (use baton-tdd-kotlin).
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
