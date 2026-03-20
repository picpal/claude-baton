# Tier 2 Code Review Rubric — 3 Reviewers

## 1. Security Guardian

| Verdict | Criteria |
|---------|----------|
| Critical | CRITICAL/HIGH pattern found from security-pattern-library → Immediately execute Security Rollback Protocol |
| Warning | MEDIUM pattern found |
| Pass | No security issues |

### Security patterns checked
- Key/secret exposure
- Auth bypass
- SQL Injection / RCE
- Privilege escalation
- Sensitive info logging
- Missing encryption

---

## 2. Quality Inspector

| Verdict | Criteria |
|---------|----------|
| Critical | Duplicate code 30+ lines / function length 50+ lines / numerous magic numbers |
| Warning | Unclear naming / missing comments for complex logic |
| Pass | Quality standards met |

### Quality checks
- Code duplication detection
- Function size and complexity
- Magic number / hardcoded value audit
- Naming clarity and self-documenting code
- Comment coverage on non-obvious logic

---

## 3. TDD Enforcer

| Verdict | Criteria |
|---------|----------|
| Critical | Implementation code without tests / coverage below 60% |
| Warning | Coverage 60-80% / edge cases not tested |
| Pass | TDD principles followed |

### TDD checks
- Test-first evidence (test commits before implementation)
- Branch coverage percentage
- Edge case and boundary testing
- Test isolation (no cross-test dependencies)
