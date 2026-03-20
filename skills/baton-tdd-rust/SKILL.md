---
name: baton-tdd-rust
description: |
  Rust TDD rules and QA checklist. Based on cargo test, cargo-tarpaulin, cargo clippy.
  Use this skill when: TDD rules are needed for a Rust project with Cargo.toml.
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
