---
name: baton-tdd-swift
description: |
  TDD rules and QA checklist for Swift projects.
  Extends baton-tdd-base with Swift-specific frameworks,
  security rules, and quality checks.
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
