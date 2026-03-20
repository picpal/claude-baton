---
name: baton-tdd-swift
description: |
  Swift TDD 규칙 및 QA 체크리스트. XCTest, XCUITest, Xcode Code Coverage 기반.
  Use this skill when: Swift/iOS/macOS 프로젝트의 TDD 규칙이 필요할 때.
  Trigger: "Swift TDD", "iOS 테스트", "macOS 테스트", "XCTest 규칙", "Swift 프로젝트 테스트".
  Covers: Keychain for secrets (no UserDefaults for sensitive data), certificate pinning.
  NOT for: Python/Go/Rust/Java projects — use the corresponding baton-tdd-{lang} skill instead.
  Extends baton-tdd-base with Swift-specific frameworks (XCTest, XCUITest),
  security rules (Keychain, no UserDefaults for secrets), and Xcode Code Coverage.
extends: baton-tdd-base
allowed-tools: Read, Write, Bash
---

# TDD Enforcer — Swift

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

## QA Checklist

### Swift Specific Verification
- [ ] All XCTest passing
- [ ] Xcode Code Coverage 80% or above
- [ ] Keychain usage confirmed (sensitive data)
- [ ] No sensitive data stored in UserDefaults
- [ ] Force unwrap (!) minimized
