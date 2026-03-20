---
name: baton-tdd-react-native
description: |
  TDD skill for React Native bare workflow projects — Detox E2E, react-native-keychain, native module mocks.
  Platform-specific (iOS/Android) testing with @testing-library/react-native.
  NOT for Expo projects (use baton-tdd-expo if app.json/app.config.js or expo dependency exists).
  NOT for plain React web (use baton-tdd-react) or Next.js (use baton-tdd-next).
  Triggers when: package.json has react-native dependency BUT NO expo dependency.
  Extends baton-tdd-react with React Native-specific testing frameworks, security rules, and quality checks.
extends: baton-tdd-react
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — React Native

## Additional Frameworks
- Jest + @testing-library/react-native
- E2E: Detox

## React Native-Specific Security Rules
- Sensitive data storage: do not use AsyncStorage → use react-native-keychain
- API keys: .env file + react-native-config

## QA Checklist

### React Native-Specific Verification
- [ ] Platform-specific (iOS/Android) rendering confirmed
- [ ] Native module mocks are appropriate
- [ ] No sensitive data stored in AsyncStorage
