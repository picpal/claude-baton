---
name: baton-review-rubric
description: |
  Use this skill when the user asks for: code review, 코드 리뷰, PR review,
  PR 검토, review rubric, review checklist, 리뷰 기준, 코드 검토,
  security review, quality review, TDD review, or any code inspection task.
  Provides Critical/Warning/Pass verdict rubric for Tier 2 (3 reviewers)
  and Tier 3 (5 reviewers) code reviews.
allowed-tools: Read
---

# Code Review — Final Verdict Rules

| Condition | Action |
|-----------|--------|
| Security Critical | Immediately execute Security Rollback Protocol |
| Any other Critical (1+) | Report to Main → Task Manager recursion |
| Warnings only | Add improvement items to todo.md and complete |
| All Pass | Approve completion |

Tier 2 rubric (3 reviewers): see `references/tier2-rubric.md`
Tier 3 rubric (5 reviewers): see `references/tier3-rubric.md`
