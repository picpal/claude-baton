---
name: baton:auto
description: |
  Toggle auto-mode on/off. Controls whether pipeline phases advance automatically.
  파이프라인 자동/수동 모드 전환.
argument-hint: "[on|off]"
---

# /baton:auto

자동 파이프라인 진행 모드를 전환합니다.

## Usage
- `/baton:auto` — 현재 상태 표시
- `/baton:auto on` — 자동 모드 (기본값, 단계 자동 진행)
- `/baton:auto off` — 수동 모드 (단계별 수동 실행)

## Steps

### 인자 없음 → 상태 표시
1. 현재 autoMode 읽기:
```bash
source hooks/scripts/state-manager.sh && state_read "autoMode"
```
2. 결과 출력:
```
Auto-mode: {ON|OFF}
Pipeline will {auto-advance to next phase|wait for manual phase commands} after agent completion.
```

### `on` 인자 → 자동 모드 활성화
```bash
source hooks/scripts/state-manager.sh && state_write "autoMode" "true"
```

### `off` 인자 → 수동 모드 활성화
```bash
source hooks/scripts/state-manager.sh && state_write "autoMode" "false"
```

## 수동 모드 동작
- 에이전트 완료 시 phaseFlag는 업데이트되지만 currentPhase는 자동 진행되지 않음
- 사용자가 `/baton:{phase}` 명령어로 다음 단계를 수동 트리거
- **예외**: Worker→QA 연쇄는 TDD 원칙 보호를 위해 항상 자동 실행
- Regression (QA 실패 재시도, Security Rollback)도 항상 자동 실행

## 수동 모드에서 사용 가능한 Phase 명령어
| 명령어 | Phase | 산출물 |
|--------|-------|--------|
| /baton:issue | 이슈 등록 | .baton/issue.md |
| /baton:interview | 인터뷰 | 확인된 요구사항 |
| /baton:analyze | 분석 | .baton/complexity-score.md |
| /baton:plan | 플래닝 | .baton/plan.md |
| /baton:tasks | 태스크 분할 | .baton/todo.md |
| /baton:work | 워커 실행 | 커밋 → 자동 qa-unit 연쇄 |
| /baton:qa | QA | 테스트 결과 |
| /baton:review | 코드 리뷰 | .baton/review-report.md |
