# QA Checklist Skill

## 단위 테스트 QA
- [ ] 모든 테스트 파일 실행 성공
- [ ] 라인 커버리지 80% 이상
- [ ] 실패 테스트 없음
- [ ] 테스트 독립 실행 가능 (순서 의존성 없음)

## 통합 테스트 QA
- [ ] 모듈 간 인터페이스 호환
- [ ] API 엔드포인트 정상 응답
- [ ] 에러 케이스 적절 처리
- [ ] 기존 기능 regression 없음

## 멀티 스택 contract test
(complexity-score.md에 "contract test 필요: YES" 시 필수)
- [ ] API 응답 스펙 ↔ 클라이언트 fetch 코드 일치 확인
- [ ] 필드명, 타입, nullable 여부 양측 동일
- [ ] 에러 응답 포맷 일치

## 실패 처리
- 1~3회: Worker에게 수정 요청
- 3회 초과: Main에 에스컬레이션 (Task Manager 재설계 요청)
