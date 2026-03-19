# TDD Enforcer — React
# extends: stacks/typescript/tdd-enforcer.md

## 추가 프레임워크
- React Testing Library (RTL)
- @testing-library/user-event

## React 전용 규칙
- 컴포넌트 테스트: render() + screen.getBy*
- 이벤트: userEvent.click() 사용 (fireEvent 지양)
- dangerouslySetInnerHTML 사용 시 Security Guardian 즉시 보고
- XSS 방지: 외부 입력값 직접 렌더링 금지
