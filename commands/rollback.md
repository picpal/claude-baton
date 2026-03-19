---
name: baton:rollback
description: Execute security rollback to the last safe tag.
---

# /baton:rollback

Execute a security rollback to the last safe tag.

## Prerequisites
- Must have at least one safe/* tag
- Should only be triggered by Security Guardian CRITICAL/HIGH finding
  or manually by user

## Steps
1. Find the latest safe tag: git tag -l 'safe/*' --sort=-version:refname | head -1
2. Get the tag's commit hash
3. Execute bulk revert: git revert {safe-tag-hash}..HEAD --no-commit
4. Commit: git commit -m "revert: security rollback to {safe-tag}"
5. Generate .baton/reports/security-report.md
6. Create/update .baton/security-constraints.md
7. Update .baton/lessons.md
8. Force Ask Mode ON
9. Notify user

## Strictly Prohibited
- Selective per-file revert
- Revert to arbitrary commit without safe tag
