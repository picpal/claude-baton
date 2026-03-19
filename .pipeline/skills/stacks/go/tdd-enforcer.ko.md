# TDD Enforcer — Go
# extends: base/tdd-enforcer.md

## 테스트 프레임워크
- go test (내장)
- 목: testify/mock

## 테스트 실행
go test ./...
go test -coverprofile=coverage.out ./...
go tool cover -html=coverage.out

## 커버리지
- 도구: go tool cover (내장)
- 기준: 80% 이상

## Go 전용 규칙
- 에러 반환: panic 금지 → error 반환 패턴
- 시크릿: os.Getenv (하드코딩 금지)
- goroutine leak: defer + context cancel 필수

## scope-lock
할당 파일 외 수정 발견 시 → "SCOPE_EXCEED: {파일명}" Main 보고 후 대기
