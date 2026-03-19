# TDD Enforcer — Next.js
# extends: stacks/react/tdd-enforcer.md

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
