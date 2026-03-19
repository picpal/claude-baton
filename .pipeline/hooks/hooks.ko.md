# Pipeline Hooks — claude-baton

session-init        : exec.log 초기화 · .pipeline/ 디렉토리 확인

post-analysis       : complexity-score.md 저장 (스택 감지 결과 포함)

post-plan           : plan.md 저장 · [Tier3] git tag safe/baseline

post-task           : todo.md 저장 (stack 자동 태깅 완료 상태)

post-work           : todo.md 해당 task 체크 · draft commit
                      git add {scope-files}
                      git commit -m "feat(task-{id}): {summary}"

unit-qa-pass        : git tag safe/task-{id}
                      exec.log에 "QA_PASS task-{id}" 기록

integration-qa-pass : git tag safe/integration-{n}

qa-fail             : retry_count++
                      3회 초과 시 → Main에 에스컬레이션 (Task Manager 재설계)

post-review         : review-report.md 저장

security-halt       : 진행 중인 모든 에이전트 즉시 종료
                      exec.log에 SECURITY_HALT 강제 기록
                      .pipeline/reports/security-report.md 생성

rollback-complete   : security-constraints.md 생성 또는 업데이트
                      lessons.md 업데이트

pre-spawn           : [1] security-constraints.md 존재 시 컨텍스트 앞단에 자동 포함
                      [2] todo.md의 해당 task stack 필드 읽어
                          .pipeline/skills/stacks/{stack}/tdd-enforcer.md 로드
                          해당 파일 없으면 .pipeline/skills/base/tdd-enforcer.md fallback

post-complete       : lessons.md 업데이트 · 종료 알림 출력
