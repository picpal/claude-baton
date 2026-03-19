# TDD Enforcer — Python
# extends: base/tdd-enforcer.md

## 테스트 프레임워크
- pytest
- 목: unittest.mock / pytest-mock
- HTTP 테스트: httpx + respx (FastAPI), requests-mock

## 테스트 실행
pytest
pytest --cov=. --cov-report=html

## 커버리지
- 도구: coverage.py
- 기준: 80% 이상

## Python 전용 보안 규칙
- 시크릿: python-dotenv + os.environ (하드코딩 금지)
- SQL: SQLAlchemy ORM 또는 파라미터 바인딩
- 의존성: requirements.txt 또는 pyproject.toml 명시

## scope-lock
할당 파일 외 수정 발견 시 → "SCOPE_EXCEED: {파일명}" Main 보고 후 대기
