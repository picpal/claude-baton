# TDD Enforcer — React Native
# extends: stacks/react/tdd-enforcer.md

## Additional Frameworks
- Jest + @testing-library/react-native
- E2E: Detox

## React Native-Specific Security Rules
- Sensitive data storage: do not use AsyncStorage → use react-native-keychain
- API keys: .env file + react-native-config
