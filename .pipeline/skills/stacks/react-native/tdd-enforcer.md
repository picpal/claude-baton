# TDD Enforcer — React Native
# extends: stacks/react/tdd-enforcer.md

## 추가 프레임워크
- Jest + @testing-library/react-native
- E2E: Detox

## React Native 전용 보안 규칙
- 민감 정보 저장: AsyncStorage 사용 금지 → react-native-keychain 사용
- API 키: .env 파일 + react-native-config
