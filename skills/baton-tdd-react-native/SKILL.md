---
name: baton-tdd-react-native
description: |
  TDD rules and QA checklist for React Native projects.
  Extends baton-tdd-react with React Native-specific testing frameworks,
  security rules, and quality checks.
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
