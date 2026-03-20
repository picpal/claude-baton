---
name: baton-security-patterns
description: |
  Security vulnerability detector and safe-pattern enforcer.
  Triggers on: "보안 리뷰", "취약점 검사", "보안 점검", "보안 패턴",
  "security review", "vulnerability scan", "security audit",
  "security check", "security patterns", "find vulnerabilities".
  CRITICAL/HIGH findings trigger immediate Rollback.
allowed-tools: Read
---

# Security Pattern Library

## Judgment Principles
1. CRITICAL or HIGH detected → halt pipeline, trigger Rollback immediately.
2. MEDIUM or below → standard rework loop, no Rollback.
3. When in doubt, escalate to higher severity. Never downgrade without evidence.
4. Every finding must cite the exact file path and line.

## Severity Summary
| Severity | Action | Examples |
|----------|--------|----------|
| CRITICAL | Immediate Rollback | Secret exposure, SQLi, auth bypass, RCE, plaintext storage |
| HIGH | Immediate Rollback | Privilege escalation, sensitive logging, missing encryption, JWT misuse |
| MEDIUM | Standard Rework | XSS, CSRF, weak validation, weak crypto |

Detailed patterns: `references/critical-patterns.md`, `references/high-patterns.md`
Safe implementations: `references/safe-patterns.md`
