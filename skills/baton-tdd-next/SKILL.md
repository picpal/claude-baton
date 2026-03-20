---
name: baton-tdd-next
description: |
  TDD skill for Next.js framework projects — SSR/SSG, API Routes, Server/Client Components, Playwright E2E, next build verification.
  NOT for plain React SPA (use baton-tdd-react) or React Native/Expo mobile (use their respective skills).
  Triggers when: package.json has next dependency OR next.config.js/next.config.ts exists.
  Covers NEXT_PUBLIC_ env var rules, server-only data isolation, and API Route security.
  Extends baton-tdd-react with Next.js-specific testing patterns, security rules, and quality checks.
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
