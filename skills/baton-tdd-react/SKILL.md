---
name: baton-tdd-react
description: |
  TDD rules and QA checklist for React projects.
  Extends baton-tdd-typescript with React-specific testing patterns,
  security rules, and quality checks.
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
