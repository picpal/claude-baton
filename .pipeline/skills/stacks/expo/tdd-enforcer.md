# TDD Enforcer — Expo
# extends: stacks/react-native/tdd-enforcer.md

## Additional Frameworks
- E2E: Maestro (optimized for Expo environment instead of Detox)

## Test Execution
npx jest
npx jest --coverage

## Expo-Specific Security Rules
- Sensitive data storage: do not use AsyncStorage → expo-secure-store required
- API keys: app.config.js extra field + process.env combination
- Deep links: expo-linking validation logic required
