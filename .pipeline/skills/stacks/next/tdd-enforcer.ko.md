# TDD Enforcer — Next.js
# extends: stacks/react/tdd-enforcer.md

## 추가 프레임워크
- Jest + React Testing Library (컴포넌트)
- Playwright (E2E)

## Next.js 전용 규칙
- API Routes: 서버사이드 환경변수 노출 금지
- SSR: 서버에서만 접근 가능한 데이터 클라이언트 번들 포함 금지
- 빌드 검증: next build 성공 확인

## 테스트 실행
npm test
npx playwright test
