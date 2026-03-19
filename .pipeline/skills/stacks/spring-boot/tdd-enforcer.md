# TDD Enforcer — Spring Boot
# extends: stacks/java/tdd-enforcer.md

## 추가 프레임워크
- MockMvc (Spring MVC 테스트)
- @SpringBootTest + TestRestTemplate (통합 테스트)
- @DataJpaTest (레포지토리 테스트)

## Spring Boot 전용 규칙
- 테스트 슬라이스 활용: @WebMvcTest, @DataJpaTest
- Security 설정: @WithMockUser 활용
- 환경변수: application-test.yml 분리

## 테스트 실행
./gradlew test
./gradlew test jacocoTestReport
