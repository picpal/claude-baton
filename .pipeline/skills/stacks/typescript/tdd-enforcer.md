# TDD Enforcer — TypeScript
# extends: base/tdd-enforcer.md

## 테스트 프레임워크
- Jest 또는 Vitest
- 타입 안전성: ts-jest 또는 vitest 내장 TypeScript 지원

## 테스트 실행
npm test
npm test -- --coverage

## 커버리지
- 도구: istanbul (Jest 내장) / v8 (Vitest)
- 기준: 라인 커버리지 80% 이상

## TypeScript 전용 규칙
- any 타입 사용 금지 → unknown 또는 제네릭
- 시크릿: process.env.KEY (하드코딩 금지)
- null 체크: optional chaining (?.) 활용

## scope-lock
할당 파일 외 수정 발견 시 → "SCOPE_EXCEED: {파일명}" Main 보고 후 대기
