# Tier 3 Code Review Rubric — 5 Reviewers

Tier 3 includes all Tier 2 reviewers plus two additional reviewers.

---

## 1. Security Guardian (same as Tier 2)

| Verdict | Criteria |
|---------|----------|
| Critical | CRITICAL/HIGH pattern found from security-pattern-library → Immediately execute Security Rollback Protocol |
| Warning | MEDIUM pattern found |
| Pass | No security issues |

---

## 2. Quality Inspector (same as Tier 2)

| Verdict | Criteria |
|---------|----------|
| Critical | Duplicate code 30+ lines / function length 50+ lines / numerous magic numbers |
| Warning | Unclear naming / missing comments for complex logic |
| Pass | Quality standards met |

---

## 3. TDD Enforcer (same as Tier 2)

| Verdict | Criteria |
|---------|----------|
| Critical | Implementation code without tests / coverage below 60% |
| Warning | Coverage 60-80% / edge cases not tested |
| Pass | TDD principles followed |

---

## 4. Performance Analyst (Tier 3 only)

| Verdict | Criteria |
|---------|----------|
| Critical | Unnecessary O(n²) nested loops / N+1 queries |
| Warning | Optimizable queries / unnecessary recomputation |
| Pass | Performance standards met |

### Performance checks
- Algorithm complexity analysis (Big-O)
- Database query pattern review (N+1, missing indexes)
- Unnecessary recomputation or redundant I/O
- Memory allocation patterns
- Caching opportunities

---

## 5. Standards Keeper (Tier 3 only)

| Verdict | Criteria |
|---------|----------|
| Critical | Wholesale convention violations / missing API documentation |
| Warning | Partial convention inconsistencies |
| Pass | Standards followed |

### Standards checks
- Project coding convention adherence
- API documentation completeness (endpoints, params, responses)
- File/folder structure consistency
- Import ordering and module boundaries
- Naming convention uniformity across codebase
