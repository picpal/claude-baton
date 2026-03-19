---
name: baton-tdd-expo
description: |
  TDD rules and QA checklist for Expo projects.
  Extends baton-tdd-react-native with Expo-specific testing frameworks,
  security rules, and quality checks.
extends: baton-tdd-react-native
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Expo

## Additional Frameworks
- E2E: Maestro (optimized for Expo environment instead of Detox)

## Test Execution
npx jest
npx jest --coverage

## Expo-Specific Security Rules
- Sensitive data storage: do not use AsyncStorage → expo-secure-store required
- API keys: app.config.js extra field + process.env combination
- Deep links: expo-linking validation logic required

## QA Checklist

### Expo-Specific Verification
- [ ] expo-secure-store usage confirmed (sensitive data)
- [ ] app.config.js environment variable separation confirmed
- [ ] Expo SDK compatibility confirmed
