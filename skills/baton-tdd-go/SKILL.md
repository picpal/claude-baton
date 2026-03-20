---
name: baton-tdd-go
description: |
  Go TDD 규칙 및 QA 체크리스트. go test, testify, go vet, staticcheck 기반.
  Use this skill when: Go/Golang 프로젝트에 go.mod가 있고 TDD 규칙이 필요할 때.
  Trigger: "Go TDD", "Golang 테스트", "go test 규칙", "Go 프로젝트 테스트".
  Covers: goroutine leak prevention (defer + context cancel), error return pattern (no panic).
  NOT for: Python/Rust/Java/Swift projects — use the corresponding baton-tdd-{lang} skill instead.
  Extends baton-tdd-base with Go-specific frameworks (go test, testify),
  static analysis (go vet, staticcheck), and quality checks.
extends: baton-tdd-base
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Go

## Test Framework
- go test (built-in)
- Mocking: testify/mock

## Running Tests
go test ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

## Coverage
- Tool: go tool cover (built-in)
- Threshold: 80% or above

## Go Specific Rules
- Error handling: no panic → use error return pattern
- Secrets: os.Getenv (no hardcoding)
- Goroutine leak prevention: defer + context cancel required

## scope-lock
If modifications outside assigned files are detected → report "SCOPE_EXCEED: {filename}" to Main and wait

## QA Checklist

### Go Specific Verification
- [ ] go test ./... all passing
- [ ] Coverage 80% or above
- [ ] No go vet warnings
- [ ] golint / staticcheck passing
- [ ] No panic usage (error return pattern)
