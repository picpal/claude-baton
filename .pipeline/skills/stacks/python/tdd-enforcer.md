# TDD Enforcer — Python
# extends: base/tdd-enforcer.md

## Test Framework
- pytest
- Mocking: unittest.mock / pytest-mock
- HTTP testing: httpx + respx (FastAPI), requests-mock

## Running Tests
pytest
pytest --cov=. --cov-report=html

## Coverage
- Tool: coverage.py
- Threshold: 80% or above

## Python Specific Security Rules
- Secrets: python-dotenv + os.environ (no hardcoding)
- SQL: SQLAlchemy ORM or parameterized binding
- Dependencies: specify in requirements.txt or pyproject.toml

## scope-lock
If modifications outside assigned files are detected → report "SCOPE_EXCEED: {filename}" to Main and wait
