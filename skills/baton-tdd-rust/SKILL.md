---
name: baton-tdd-rust
description: |
  TDD rules and QA checklist for Rust projects.
  Extends baton-tdd-base with Rust-specific frameworks,
  security rules, and quality checks.
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
