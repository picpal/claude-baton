# Code Review Rubric

## Security Guardian (Tier 2, 3)
Critical: security-pattern-library의 CRITICAL/HIGH 패턴 발견
  → 즉시 보안 Rollback 프로토콜 실행
Warning:  MEDIUM 패턴 발견
Pass:     보안 이슈 없음

## Quality Inspector (Tier 2, 3)
Critical: 중복 코드 30줄+ / 함수 길이 50줄+ / 매직 넘버 다수
Warning:  네이밍 불명확 / 복잡 로직 주석 부재
Pass:     품질 기준 충족

## TDD Enforcer (Tier 2, 3)
Critical: 테스트 없는 구현 코드 존재 / 커버리지 60% 미만
Warning:  커버리지 60~80% / 엣지 케이스 미테스트
Pass:     TDD 원칙 준수

## Performance Analyst (Tier 3 전용)
Critical: O(n²) 불필요 중첩 루프 / N+1 쿼리
Warning:  최적화 가능한 쿼리 / 불필요한 재계산
Pass:     성능 기준 충족

## Standards Keeper (Tier 3 전용)
Critical: 컨벤션 전면 위반 / API 문서 없음
Warning:  일부 컨벤션 불일치
Pass:     표준 준수

## 최종 판정 규칙
- Security Critical       → 즉시 보안 Rollback 프로토콜
- 그 외 Critical 1개 이상 → Main 보고 → Task Manager 재귀
- Warning만               → todo.md에 개선 항목 추가 후 완료
- 전체 Pass               → 완료 승인
