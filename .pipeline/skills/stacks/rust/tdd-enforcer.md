# TDD Enforcer — Rust
# extends: base/tdd-enforcer.md

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
