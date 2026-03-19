# Security Pattern Library

## CRITICAL — 즉시 Rollback 트리거
- 하드코딩된 시크릿/API 키/비밀번호
  예: const SECRET = "abc123", apiKey = "sk-..."
- SQL Injection (비파라미터 쿼리)
  예: `SELECT * FROM users WHERE id = ${userId}`
- 인증 우회 가능 코드 패턴
- RCE 가능 입력 처리 (eval, exec 등)
- 민감 데이터 평문 저장

## HIGH — 즉시 Rollback 트리거
- 불충분한 접근 제어 (권한 상승 가능)
- 민감 정보 로그 출력 (비밀번호, 토큰, PII)
- 암호화 없는 민감 데이터 전송
- JWT secret 환경변수 미사용

## MEDIUM 이하 — 일반 재작업
- XSS 취약점
- CSRF 토큰 미검증
- 불충분한 입력 검증
- 취약한 암호화 알고리즘

## 안전한 구현 패턴
- 시크릿:     process.env.SECRET_KEY (절대 하드코딩 금지)
- SQL:        ORM 또는 파라미터 바인딩
- 비밀번호:  bcrypt / argon2 해싱
- JWT:        환경변수 secret + 만료시간 설정
- 입력값:    화이트리스트 검증
