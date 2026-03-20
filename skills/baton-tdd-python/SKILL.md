---
name: baton-tdd-python
description: |
  Python TDD 규칙 및 QA 체크리스트. pytest, coverage.py, mypy, python-dotenv, SQLAlchemy 기반.
  Use this skill when: Python/Django/Flask/FastAPI 프로젝트의 TDD 규칙이 필요할 때.
  Trigger: "파이썬 TDD", "Python 테스트", "pytest 규칙", "FastAPI 테스트", "Django TDD", "Flask 테스트".
  NOT for: Go/Rust/Java/Swift projects — use the corresponding baton-tdd-{lang} skill instead.
  Extends baton-tdd-base with Python-specific frameworks (pytest, coverage.py, mypy),
  security rules (python-dotenv, SQLAlchemy ORM), and quality checks.
extends: baton-tdd-base
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Python

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

## QA Checklist

### Python Specific Verification
- [ ] All pytest tests passing
- [ ] Coverage 80% or above
- [ ] Type hints applied (mypy passing recommended)
- [ ] Dependencies specified in requirements.txt / pyproject.toml
