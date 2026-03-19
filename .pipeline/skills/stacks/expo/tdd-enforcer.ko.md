# TDD Enforcer — Expo
# extends: stacks/react-native/tdd-enforcer.md

## 추가 프레임워크
- E2E: Maestro (Detox 대신 Expo 환경에 최적화)

## 테스트 실행
npx jest
npx jest --coverage

## Expo 전용 보안 규칙
- 민감 정보 저장: AsyncStorage 사용 금지 → expo-secure-store 필수
- API 키: app.config.js의 extra 필드 + process.env 조합
- 딥링크: expo-linking 검증 로직 필수
