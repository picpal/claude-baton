# TDD Enforcer — Go
# extends: base/tdd-enforcer.md

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
