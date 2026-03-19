# TDD Enforcer — Rust
# extends: base/tdd-enforcer.md

## 테스트 프레임워크
- 내장 #[test] / #[cfg(test)]
- 통합 테스트: tests/ 디렉토리

## 테스트 실행
cargo test
cargo tarpaulin --out Html

## 커버리지
- 도구: cargo-tarpaulin
- 기준: 80% 이상

## Rust 전용 규칙
- unsafe 블록: Security Guardian 즉시 감사 대상
- unwrap() 금지 → expect() 또는 ? 연산자
- 시크릿: std::env::var (하드코딩 금지)

## scope-lock
할당 파일 외 수정 발견 시 → "SCOPE_EXCEED: {파일명}" Main 보고 후 대기
