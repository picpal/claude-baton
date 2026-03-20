---
name: baton-qa-checklist
description: |
  QA gate for test results. Invoke this skill whenever the user asks you to: judge if tests
  passed or failed, check coverage against a threshold, diagnose regression vs new bug from
  test output, verify API contract field/type matching between backend and frontend, escalate
  repeated test failures, or decide whether a task is ready for code review based on test outcomes.
  Covers pytest, JUnit, integration tests, and multi-stack contract verification.
  테스트 결과 판정, 커버리지 판단, QA 합격/불합격, regression 분석, API 스펙 일치 검증,
  반복 실패 에스컬레이션에 사용하세요.
  Do NOT use for writing tests, running tests, explaining test code, code style review,
  or performance optimization.
allowed-tools: Read, Bash, TaskUpdate, TaskGet
---

# QA Checklist Skill

## Unit Test QA
- [ ] All test files execute successfully
- [ ] Line coverage 80% or above
- [ ] No failing tests
- [ ] Tests can run independently (no order dependency)

## Integration Test QA
- [ ] Inter-module interface compatibility
- [ ] API endpoints respond correctly
- [ ] Error cases handled properly
- [ ] No regression in existing functionality

## Multi-Stack Contract Test
(Mandatory when complexity-score.md shows "contract test required: YES")
- [ ] API response spec ↔ client fetch code match verified
- [ ] Field names, types, and nullable status are identical on both sides
- [ ] Error response format is consistent

## Failure Handling
- Attempts 1-3: Request fix from Worker + `TaskUpdate(status: "blocked")`
- Beyond 3 attempts: `TaskUpdate(status: "escalated")` + Escalate to Main (request Task Manager redesign)
- On QA pass: no status change needed (Worker's "done" status is retained)
