# TDD Enforcer — Spring Boot
# extends: stacks/java/tdd-enforcer.md

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
