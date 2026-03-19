---
name: baton-tdd-go
description: |
  TDD rules and QA checklist for Go projects.
  Extends baton-tdd-base with Go-specific frameworks,
  security rules, and quality checks.
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
