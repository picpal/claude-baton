# TDD Enforcer Skill (Base)

## 절대 원칙: 테스트 코드 → 구현 코드 순서

## TDD 사이클
1. RED      — 실패하는 테스트 작성
2. GREEN    — 테스트를 통과하는 최소 구현
3. REFACTOR — 코드 정리 (테스트는 계속 통과)

## 테스트 작성 기준
- 함수/메서드 단위 테스트
- 정상 케이스 + 엣지 케이스 + 실패 케이스
- 테스트 이름: "should ..." 형식

## scope-lock 규칙
할당된 파일 외 수정 발견 시:
1. 즉시 작업 중단
2. Main에 "SCOPE_EXCEED: {파일명}" 보고
3. Main 승인 대기

## 커밋 메시지 형식
feat(task-{id}): {한 줄 요약}
test(task-{id}): {테스트 설명}
fix(task-{id}):  {수정 내용}
