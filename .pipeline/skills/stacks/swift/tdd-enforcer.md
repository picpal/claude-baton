# TDD Enforcer — Swift
# extends: base/tdd-enforcer.md

## 테스트 프레임워크
- XCTest (내장)
- UI 테스트: XCUITest

## 테스트 실행
xcodebuild test -scheme {SchemeName} -destination 'platform=iOS Simulator,name=iPhone 15'

## 커버리지
- 도구: Xcode Code Coverage
- 기준: 라인 커버리지 80% 이상

## Swift 전용 보안 규칙
- 민감 정보: Keychain 사용 필수 (UserDefaults 금지)
- 인증서 pinning: URLSession delegate 구현
- 하드코딩 금지: Info.plist + 환경 변수 분리

## scope-lock
할당 파일 외 수정 발견 시 → "SCOPE_EXCEED: {파일명}" Main 보고 후 대기
