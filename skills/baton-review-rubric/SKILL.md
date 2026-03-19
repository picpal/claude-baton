---
name: baton-review-rubric
description: |
  Code review rubric for Security Guardian, Quality Inspector, TDD Enforcer,
  Performance Analyst (Tier 3), and Standards Keeper (Tier 3).
  Defines Critical/Warning/Pass verdicts and final judgment rules.
allowed-tools: Read
---

# Code Review Rubric

## Security Guardian (Tier 2, 3)
Critical: CRITICAL/HIGH pattern found from security-pattern-library
  → Immediately execute Security Rollback Protocol
Warning:  MEDIUM pattern found
Pass:     No security issues

## Quality Inspector (Tier 2, 3)
Critical: Duplicate code 30+ lines / function length 50+ lines / numerous magic numbers
Warning:  Unclear naming / missing comments for complex logic
Pass:     Quality standards met

## TDD Enforcer (Tier 2, 3)
Critical: Implementation code without tests / coverage below 60%
Warning:  Coverage 60-80% / edge cases not tested
Pass:     TDD principles followed

## Performance Analyst (Tier 3 only)
Critical: Unnecessary O(n²) nested loops / N+1 queries
Warning:  Optimizable queries / unnecessary recomputation
Pass:     Performance standards met

## Standards Keeper (Tier 3 only)
Critical: Wholesale convention violations / missing API documentation
Warning:  Partial convention inconsistencies
Pass:     Standards followed

## Final Verdict Rules
- Security Critical       → Immediately execute Security Rollback Protocol
- Any other Critical (1+) → Report to Main → Task Manager recursion
- Warnings only           → Add improvement items to todo.md and complete
- All Pass                → Approve completion
