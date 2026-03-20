---
name: baton-tdd-react
description: |
  TDD skill for React web component projects — React 컴포넌트, JSX, RTL, dangerouslySetInnerHTML 보안 검증.
  React Testing Library (RTL) + userEvent 기반 컴포넌트/이벤트 테스트.
  NOT for React Native/Expo (use baton-tdd-react-native or baton-tdd-expo) or Next.js (use baton-tdd-next).
  Triggers when: package.json has react dependency BUT NO react-native, expo, or next dependency.
  Extends baton-tdd-typescript with React-specific testing patterns, security rules, and quality checks.
extends: baton-tdd-typescript
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — React

## Additional Frameworks
- React Testing Library (RTL)
- @testing-library/user-event

## React-Specific Rules
- Component tests: render() + screen.getBy*
- Events: use userEvent.click() (avoid fireEvent)
- If dangerouslySetInnerHTML is used, report to Security Guardian immediately
- XSS prevention: do not directly render external input values

## QA Checklist

### React-Specific Verification
- [ ] Component rendering tests exist
- [ ] User event tests exist
- [ ] Basic accessibility (a11y) verification
- [ ] No missing key props
