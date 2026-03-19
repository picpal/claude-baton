---
name: baton-tdd-next
description: |
  TDD rules and QA checklist for Next.js projects.
  Extends baton-tdd-react with Next.js-specific testing patterns,
  security rules, and quality checks.
extends: baton-tdd-react
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Next.js

## Additional Frameworks
- Jest + React Testing Library (components)
- Playwright (E2E)

## Next.js-Specific Rules
- API Routes: do not expose server-side environment variables
- SSR: do not include server-only accessible data in client bundles
- Build verification: confirm next build succeeds

## Test Execution
npm test
npx playwright test

## QA Checklist

### Next.js-Specific Verification
- [ ] next build succeeds
- [ ] Server Component / Client Component separation is appropriate
- [ ] API Route response format is consistent
- [ ] NEXT_PUBLIC_ prefix used appropriately for environment variables
