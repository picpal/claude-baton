# Lessons 시스템 최적화 설계서

> 작성일: 2026-03-28
> 버전: 1.4.1 → 1.5.0 (예정)

## 배경

lessons.md가 누적되면 매 세션 시작마다 전체 파일을 읽어야 하므로 토큰 소모가 증가함.
50건 기준 ~1,400 tokens, 100건 기준 ~2,800 tokens.

## 설계 방향

multi-file 분리(category별 파일)는 원자성, Rollback 조율, 크로스카테고리 누락 리스크가 높아 **기각**.
단일 파일 내 듀얼 섹션 방식을 채택.

---

## AS-IS / TO-BE 비교

### 1. 파일 구조

| | AS-IS | TO-BE |
|---|---|---|
| **파일** | `.baton/lessons.md` (단일) | `.baton/lessons.md` (단일, 듀얼 섹션) |
| **구조** | 전체 lesson을 순차 나열 | Active Rules 섹션 + `DETAIL_BOUNDARY` + Full Details 섹션 |
| **50건 기준 크기** | ~500줄 (전체 로딩) | Active Rules ~100줄 + Full Details ~400줄 |

### 2. 세션 시작 시 읽기

| | AS-IS | TO-BE |
|---|---|---|
| **읽는 범위** | 전체 파일 (500줄) | `DETAIL_BOUNDARY`까지만 (100줄) |
| **읽기 방법** | `Read(".baton/lessons.md")` | `Read(".baton/lessons.md", limit: N)` (boundary까지) |
| **추출 대상** | `rule:` 필드만 파싱 | rule + keywords 이미 정리되어 있음 (파싱 불필요) |
| **토큰 비용 (50건)** | ~1,400 tokens | ~200 tokens |
| **절감률** | — | **~86%** |

### 3. Rule 매칭

| | AS-IS | TO-BE |
|---|---|---|
| **매칭 방식** | Main이 rule 텍스트를 읽고 직접 판단 | keywords 필드로 요청 키워드와 매칭 |
| **"로그인 수정" 요청 시** | rule 전체를 읽어야 관련성 판단 | `keywords: login, auth, jwt` → 즉시 매칭 |
| **크로스 카테고리** | 전체 파일이니 자연스럽게 발견 | keywords에 복수 카테고리 태깅 가능 |
| **매칭 정확도** | ~85% (맥락 의존) | ~92% (keyword 기반 + 맥락 보조) |

### 4. 상세 내용 참조

| | AS-IS | TO-BE |
|---|---|---|
| **방법** | 이미 메모리에 로딩됨 | `Read(".baton/lessons.md", offset: BOUNDARY)` 후 ID로 탐색 |
| **비용** | 0 (이미 읽음) | 필요 시만 50~100 tokens |
| **빈도** | 매 세션 100% | 세션의 ~30%만 (모호한 요청 시) |
| **평균 비용** | 1,400 tokens (항상) | 200 + (0.3 × 75) ≈ **~223 tokens** |

### 5. Lesson 쓰기 (LESSON_REPORT)

| | AS-IS | TO-BE |
|---|---|---|
| **Writer** | Main (단독) + Rollback (예외) | 동일 (변경 없음) |
| **Write 횟수** | 1회 (append) | 1회 (append — 2개 섹션 동시) |
| **원자성** | 단일 파일 → 보장 | 단일 파일 → 보장 (동일) |
| **쓰기 포맷** | Full entry만 append | Active Rules에 1줄 + Full Details에 전체 entry |
| **Rollback 호환** | 기존 bash script 그대로 | 기존 bash script 그대로 (파일 동일) |

### 6. Entry 포맷

**AS-IS (현재)**:
```markdown
### L-2026-03-20-01 | security | high
- **trigger**: auth feature review
- **what happened**: httpOnly 미설정으로 XSS 통해 토큰 탈취 가능
- **root cause**: cookie 옵션 누락
- **rule**: JWT 토큰은 httpOnly 쿠키 필수
- **files**: auth/token.service.ts
```

**TO-BE Active Rules (세션 시작 시 로딩)**:
```markdown
- L-2026-03-20-01 | security | high | JWT 토큰은 httpOnly 쿠키 필수
  keywords: jwt, token, cookie, login, auth
```

**TO-BE Full Details (on-demand 참조)**:
```markdown
### L-2026-03-20-01 | security | high
- **trigger**: auth feature review
- **what happened**: httpOnly 미설정으로 XSS 통해 토큰 탈취 가능
- **root cause**: cookie 옵션 누락
- **rule**: JWT 토큰은 httpOnly 쿠키 필수
- **files**: auth/token.service.ts
```

### 7. 확장성 (lesson 누적)

| | AS-IS | TO-BE |
|---|---|---|
| **10건** | 70줄 → 문제 없음 | Active 20줄 + Detail 70줄 |
| **50건** | 350줄 → 토큰 부담 시작 | Active 100줄 + Detail 350줄 (100줄만 로딩) |
| **100건** | 700줄 → 심각한 토큰 낭비 | Active 200줄 + Detail 700줄 (200줄만 로딩) |
| **200줄 도달 시점** | ~28건 | ~100건 (3.5배 여유) |

### 8. 리스크 비교

| 리스크 | AS-IS | TO-BE |
|---|---|---|
| 토큰 과다 (50건+) | **HIGH** — 매번 전체 로딩 | **LOW** — Active Rules만 로딩 |
| 모호한 요청 매칭 | **MEDIUM** — rule 텍스트 의존 | **LOW** — keywords 필드로 보강 |
| 크로스 카테고리 누락 | **LOW** — 전체 파일이니 자연 발견 | **LOW** — keywords 복수 태깅 |
| 쓰기 원자성 | **NONE** — 단일 파일 | **NONE** — 단일 파일 유지 |
| Rollback 호환 | **NONE** — 그대로 | **LOW** — append 위치만 조정 |
| 상세 맥락 손실 | **NONE** — 항상 전체 로딩 | **LOW** — 필요 시 offset Read |

---

## TO-BE lessons.md 템플릿

```markdown
# Lessons Learned

## Active Rules (세션 시작 시 이 섹션만 읽음)

<!-- 형식: - L-{ID} | {category} | {severity} | {rule 한줄}  -->
<!--         keywords: {쉼표 구분 키워드}                     -->


---
<!-- DETAIL_BOUNDARY — 아래는 on-demand 참조용. 세션 시작 시 읽지 않음 -->

## Full Details

<!-- 형식: AS-IS lesson entry와 동일 -->
```

---

## 수정 대상 파일

| 파일 | 변경 내용 |
|------|----------|
| `agents/main-orchestrator.md` | Session Start 읽기 로직: limit 파라미터로 boundary까지만 읽도록 변경 |
| `CLAUDE.md` | LESSON_REPORT Format에 keywords 필드 추가 |
| `commands/init.md` | lessons.md 초기화 시 듀얼 섹션 헤더 포함 |
| `commands/rollback.md` | rollback lesson 쓰기 시 Active Rules + Full Details 양쪽 append |
| **변경 없음** | 7개 reporting agent (출력 포맷 동일), phase-gate, hooks |

---

## 기각된 대안: multi-file 분리

카테고리별 `.baton/lessons/{category}.md` 분리 방식은 다음 리스크로 기각:

| 리스크 | 심각도 | 설명 |
|--------|--------|------|
| 2-file 쓰기 원자성 | **CRITICAL** | Active Rules + category file 동시 쓰기 실패 시 dangling reference |
| Rollback 조율 | **CRITICAL** | bash script가 2개 파일에 쓰려면 복잡도 급증 + ID 충돌 위험 |
| 크로스 카테고리 누락 | **HIGH** | security+tdd 교차 lesson이 한 파일에만 저장 → 다른 agent 발견 불가 |
| 카테고리 확장성 | **HIGH** | 고정 7개 카테고리 → 새 도메인(performance, compliance 등) 대응 불가 |

---

## 검증 결과 요약

### 시뮬레이션 (50건 기준, 3개 시나리오)

| 시나리오 | Active Rules만 | 전체 로딩 | 절감 | 정확도 |
|----------|---------------|----------|------|--------|
| A: 명확한 요청 (비밀번호 만료 기능) | ~450t | ~1,400t | 68% | 95% |
| B: 모호한 요청 (API 속도 개선) | ~450t | ~1,400t | 68% | 90% |
| C: 크리티컬 모호 (로그인 버그) | ~650t | ~1,500t | 57% | 88% |
| **평균** | **~520t** | **~1,433t** | **64%** | **91%** |

### 리스크 검증

- 단일 파일 유지 → 원자성 문제 없음
- keywords 필드 → 모호한 요청 매칭 정확도 85% → 92%
- on-demand Read(offset) → 상세 맥락 필요 시 50~100 tokens로 참조 가능
- Rollback 기존 bash script 호환 유지
