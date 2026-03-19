# Pipeline Rules — claude-baton

R01 공정 외 작업 금지    : 전 에이전트 — 자신의 Phase 외 작업 수행 불가.
                           위반 시 즉시 중단 후 Main 보고.

R02 scope-lock          : Worker — todo.md 명시 파일 외 수정 불가.
                           초과 발견 시 "SCOPE_EXCEED: {파일}" 보고 후 Main 승인 대기.

R03 test-first          : Worker — 구현 코드 작성 전 테스트 코드 반드시 선작성.

R04 Rollback 권한       : Security Guardian만 CRITICAL/HIGH Rollback 선언 가능.
                           타 에이전트 보안 이슈 발견 시 → Main 보고 → Security Guardian 확인 요청.

R05 부분 revert 금지    : Main — 보안 Rollback은 safe 태그 기준 전체 일괄 revert.
                           파일 단위 선택적 revert 금지.

R06 Ask Mode            : Tier 3 진입 시 / 보안 Rollback 재진입 시 강제 ON.

R07 Tier 강등 금지      : Main — 승격된 Tier는 세션 내 유지. 하향 판단 불가.

R08 CRITICAL/HIGH만     : Security Guardian — MEDIUM 이하는 일반 재작업 루프 처리.

R09 safe 태그 조건      : Main — QA 통과 확인 후에만 safe 태그 부여.

R10 충돌 에스컬레이션   : Main — Tier 3 Planning 충돌(보안↔개발) 시
                           반드시 사용자에게 트레이드오프 제시 후 결정 요청.

R11 스택 가정 금지      : 분석 에이전트 — 기술 스택을 절대 가정하지 않는다.
                           반드시 빌드 파일(package.json, build.gradle 등)에서 읽어 확정.
                           감지 실패 시 Main 보고 후 사용자에게 확인 요청.

R12 멀티 스택 task 분리 : Task Manager — 하나의 task가 두 스택에 걸치면
                           반드시 스택별로 분리하여 별도 task로 생성.
