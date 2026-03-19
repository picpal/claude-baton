# TDD Enforcer — Swift
# extends: base/tdd-enforcer.md

## Test Framework
- XCTest (built-in)
- UI testing: XCUITest

## Running Tests
xcodebuild test -scheme {SchemeName} -destination 'platform=iOS Simulator,name=iPhone 15'

## Coverage
- Tool: Xcode Code Coverage
- Threshold: line coverage 80% or above

## Swift Specific Security Rules
- Sensitive data: Keychain usage required (no UserDefaults)
- Certificate pinning: implement URLSession delegate
- No hardcoding: separate into Info.plist + environment variables

## scope-lock
If modifications outside assigned files are detected → report "SCOPE_EXCEED: {filename}" to Main and wait
