# Codebase Scanner Skill

## 역할
코드베이스 구조를 파악하고 기술 스택을 자동 감지한다.
감지 결과는 complexity-score.md에 기록하며 이후 모든 에이전트 spawn 시 참조된다.
절대로 스택을 가정하지 않는다. 반드시 파일에서 읽어서 확정한다.

## 1차 스캔 (인터뷰 대기 중 병렬 수행)

### 스택 자동 감지 순서
1. 루트 및 각 디렉토리에서 아래 파일 탐색:
   - package.json            → JS/TS 계열 판별
   - build.gradle            → Java / Kotlin / Spring Boot 판별
   - pom.xml                 → Java / Maven 판별
   - requirements.txt / pyproject.toml → Python 판별
   - go.mod                  → Go 판별
   - Cargo.toml              → Rust 판별
   - Package.swift / *.xcodeproj → Swift 판별
   - app.json / app.config.js → Expo 판별

2. package.json 발견 시 dependencies 확인:
   - "react-native" 있음       → react-native
   - "expo" 있음               → expo (react-native extends)
   - "next" 있음               → next
   - "react" 있음 (위 없으면)  → react
   - 위 모두 없으면            → typescript (또는 node)

3. build.gradle / pom.xml 발견 시:
   - "org.springframework.boot" 있음 → spring-boot (java extends)
   - kotlin plugin 있음              → kotlin (java extends)
   - 위 없으면                       → java

4. 디렉토리별 매핑 확정:
   예) backend/ → spring-boot, mobile/ → expo

### 파일 → 스택 매핑 규칙 (보조)
- *.java, *.kt    → java / kotlin
- *.swift         → swift
- *.py            → python
- *.go            → go
- *.rs            → rust
- *.tsx, *.ts     → 상위 디렉토리 스택 따름 (빌드 파일 감지 우선)

## 2차 스캔 (요구사항 확정 후)
- 변경 영향 받을 파일 목록
- 관련 인터페이스 및 타입 정의
- 의존성 그래프 (변경 대상 기준)
- 스택 간 API 인터페이스 존재 여부 확인 (멀티 스택 시 contract test 필요 여부)

## 산출물: complexity-score.md 형식
```
## 감지된 스택
| 경로      | 스택        | 근거 파일                              |
|-----------|-------------|----------------------------------------|
| backend/  | spring-boot | build.gradle (spring-boot-starter-web) |
| mobile/   | expo        | package.json (expo ^51.0.0)            |

## 파일 → 스택 매핑
*.java, *.kt (backend/) → spring-boot / kotlin
*.tsx, *.ts  (mobile/)  → expo / react-native

## 멀티 스택 여부
- 멀티 스택: YES
- API contract test 필요: YES (backend ↔ mobile 인터페이스 존재)

## 복잡도 스코어
- 변경 예상 파일 수: N개 (Npt)
- 크로스 서비스 의존성: 있음/없음
- 신규 기능: 있음/없음
- 아키텍처 결정: 있음/없음
- 보안 관련: 있음/없음
→ 총점: Npt → Tier N
```
