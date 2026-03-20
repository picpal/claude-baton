---
name: baton-tdd-swift
description: |
  Swift TDD rules and QA checklist. Based on XCTest, XCUITest, Xcode Code Coverage.
  Use this skill when: TDD rules are needed for a Swift/iOS/macOS project.
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
