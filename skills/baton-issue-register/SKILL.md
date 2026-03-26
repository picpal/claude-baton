---
name: baton-issue-register
description: |-
  Register or link a GitHub Issue at pipeline start. Tier 2/3: always. Tier 1: bug/fix requests only.
  Auto-creates a new issue when no existing issue is referenced,
  or links an existing issue when the user references one (e.g., #123).
  Auto-labels based on request type (bug, feature, refactor).
  Triggered by Main Orchestrator as Phase 0 before Interview (Tier 2/3) or Analysis (Tier 1).
  이슈 등록, GitHub 이슈 생성, 이슈 연결, #123 해결해줘.
allowed-tools: Read, Write, Bash
model: sonnet
---

# Issue Registration — Phase 0 (Tier 2/3 always, Tier 1 bug/fix only)

Register or link a GitHub Issue for pipeline traceability. Tier 2/3: always. Tier 1: bug/fix requests only.

## Pre-flight Checks

Run these checks before proceeding:

1. **gh CLI authentication**: Run `gh auth status`. If it fails, log a warning, set `issueRegistered: true` in state.json (so pipeline continues), write `.baton/issue.md` with `Number: none`, and stop. The pipeline proceeds without issue tracking.
2. **Git remote**: Run `git remote -v`. If no remote exists, same graceful skip as above.

## Existing Issue Detection

Parse the user's original request for issue references:
- Patterns: `#\d+`, `이슈 \d+`, `issue \d+` (case-insensitive)
- If found, validate with: `gh issue view <number> --json number,url,labels,title`
- If the issue doesn't exist, inform the user and create a new one instead

## Request Type Classification (Auto-labeling)

| Keywords | Label |
|----------|-------|
| 버그, bug, fix, 수정 | `bug` |
| 추가, 기능, feature, add, 새로운, 구현 | `enhancement` |
| 리팩토링, refactor, 정리, 개선 | `refactor` |
| 문서, docs, README | `documentation` |
| (default) | `enhancement` |

Scan the user's request text for these keywords. Use the first match found.

## Tier 1 Condition
For Tier 1 requests, Phase 0 is only triggered when the request matches bug/fix keywords:
- Korean: 버그, 수정, 오류, 에러
- English: bug, fix, error

If the request does not match these keywords in Tier 1, skip Phase 0 entirely.

## Issue Creation

When no existing issue is detected:

```bash
gh issue create --title "<Korean summary, max 60 chars>" --label "<detected-label>" --body "<full original request text>"
```

- Title: Concise Korean summary of the user's request
- Body: The complete original request text for traceability

## Artifact Recording

Write `.baton/issue.md`:

```markdown
# Issue Tracking
- Number: #<issue-number>
- URL: <issue-url>
- Labels: <label>
- Existing: <true|false>
- Created: <ISO 8601 timestamp>
```

## State Update

Update state.json fields using Bash with state_write calls:

```bash
source hooks/scripts/state-manager.sh
state_write "issueNumber" "<number>"
state_write "issueUrl" "<url>"
state_write "issueLabels" '["<label>"]'
state_write "isExistingIssue" "<true|false>"
state_write "phaseFlags.issueRegistered" "true"
```

## Pipeline Resume

If `phaseFlags.issueRegistered` is already `true` and `.baton/issue.md` exists, skip Phase 0 entirely.

## Pipeline Completion

Main Orchestrator handles issue closure at pipeline end:
- Runs `gh issue close #N --comment "파이프라인 완료 — 자동 종료"` for both auto-created and existing issues
