---
name: baton-tdd-rust
description: |
  Rust TDD 규칙 및 QA 체크리스트. cargo test, cargo-tarpaulin, cargo clippy 기반.
  Use this skill when: Rust 프로젝트에 Cargo.toml이 있고 TDD 규칙이 필요할 때.
  Trigger: "Rust TDD", "Rust 테스트", "cargo test 규칙", "Rust 프로젝트 테스트".
  Covers: unsafe block audit, no unwrap() policy (use expect() or ? operator).
  NOT for: Python/Go/Java/Swift projects — use the corresponding baton-tdd-{lang} skill instead.
  Extends baton-tdd-base with Rust-specific frameworks (cargo test, cargo-tarpaulin),
  linting (cargo clippy), security rules (unsafe audit), and quality checks.
extends: baton-tdd-base
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Rust

## Test Framework
- Built-in #[test] / #[cfg(test)]
- Integration tests: tests/ directory

## Running Tests
cargo test
cargo tarpaulin --out Html

## Coverage
- Tool: cargo-tarpaulin
- Threshold: 80% or above

## Rust Specific Rules
- unsafe blocks: subject to immediate Security Guardian audit
- No unwrap() → use expect() or ? operator
- Secrets: std::env::var (no hardcoding)

## scope-lock
If modifications outside assigned files are detected → report "SCOPE_EXCEED: {filename}" to Main and wait

## QA Checklist

### Rust Specific Verification
- [ ] All cargo test passing
- [ ] cargo tarpaulin coverage 80% or above
- [ ] No cargo clippy warnings
- [ ] unsafe block audit completed
- [ ] No unwrap() usage
