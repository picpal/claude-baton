🌐 **한국어** | [English](README.md)

# claude-baton

Claude Code용 멀티 에이전트 개발 파이프라인 플러그인.

요구사항 인터뷰부터 보안 리뷰까지 전체 개발 라이프사이클을 오케스트레이션합니다. 12개 기술 스택 자동 감지, TDD 강제 적용, 티어별 복잡도 관리를 지원합니다.

## 설치

```bash
# 1. 마켓플레이스 추가
/plugin marketplace add picpal/claude-baton

# 2. 플러그인 설치
/plugin install claude-baton@claude-baton
```

또는 로컬 개발용:

```bash
claude --plugin-dir /path/to/claude-baton
```

## 빠른 시작

```bash
# 프로젝트에서 초기화
/baton:init

# 개발 시작 — 필요한 것을 설명하세요
"JWT를 사용한 사용자 인증 추가"

# 언제든 상태 확인
/baton:status
```

## 작동 방식

### 자동 스택 감지
claude-baton은 빌드 파일(package.json, build.gradle, go.mod 등)을 읽어 기술 스택을 자동 감지합니다. 수동 설정이 필요 없습니다.

**지원 스택:** TypeScript, React, React Native, Expo, Next.js, Java, Spring Boot, Kotlin, Python, Go, Rust, Swift

### 티어별 파이프라인

| 티어 | 점수 | 파이프라인 |
|------|------|-----------|
| 1 — Light | 0-3점 | 분석 → 워커 → QA → 완료 |
| 2 — Standard | 4-8점 | 인터뷰 → 분석 → 설계 → 태스크 → 워커 → QA → 리뷰(3명) → 완료 |
| 3 — Full | 9+점 | 인터뷰 → 분석 → 설계(3명) → 태스크 → 워커 → QA → 리뷰(5명) → 완료 |

### 복잡도 점수

| 기준 | 점수 |
|------|------|
| 변경 파일 수 (최대 5) | 0–5 |
| 크로스 서비스 의존성 | +3 |
| 신규 기능 | +2 |
| 아키텍처 결정 포함 | +3 |
| 보안/인증/결제 관련 | +4 |
| DB 스키마 변경 | +3 |

### 보안 우선
- 자동 보안 패턴 스캐닝 (CRITICAL/HIGH/MEDIUM)
- Security Guardian의 독점적 롤백 권한
- 안전한 롤백 지점을 위한 safe-commit 태그
- 보안 사고 이후 보안 제약 조건 자동 주입

### TDD 강제 적용
모든 워커는 엄격한 TDD를 따릅니다: 테스트 작성 → 구현 → 리팩터링.

## 명령어

| 명령어 | 설명 |
|--------|------|
| `/baton:init` | 현재 프로젝트에서 파이프라인 초기화 |
| `/baton:status` | 파이프라인 상태 표시 |
| `/baton:auto` | 자동 모드 on/off 전환 (기본: on) |
| `/baton:issue` | 이슈 수동 등록 |
| `/baton:checkpoint` | 체크포인트 저장, 목록, 복원 |
| `/baton:rollback` | 마지막 safe 태그로 보안 롤백 |
| `/baton:tier` | 현재 티어 표시/변경 |
| `/baton:{phase}` | 단계 수동 실행: interview, analyze, plan, tasks, work, qa, review |

## 파이프라인 에이전트

| 에이전트 | 역할 | 모델 |
|----------|------|------|
| Main Orchestrator | 전체 페이즈 조율 | opus |
| Interview Agent | 요구사항 명확화 | sonnet |
| Analysis Agent | 스택 감지 + 영향 분석 | opus |
| Planning (Security/Arch/Dev) | Tier 3 설계 | opus |
| Task Manager | 태스크 분할 + 스택 태깅 | opus |
| Worker | TDD 구현 | auto |
| QA (Unit/Integration) | 테스트 검증 | sonnet |
| Security Guardian | 보안 리뷰 + 롤백 | opus |
| Quality Inspector | 코드 품질 리뷰 | sonnet |
| TDD Enforcer (Reviewer) | TDD 준수 리뷰 | sonnet |
| Performance Analyst | 성능 리뷰 (Tier 3) | sonnet |
| Standards Keeper | 표준 리뷰 (Tier 3) | sonnet |

## 설정

### 환경 변수
- `LOG_MODE`: minimal / execution (기본값) / verbose

## 라이선스

MIT
