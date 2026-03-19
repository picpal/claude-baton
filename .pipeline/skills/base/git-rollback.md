# Git Rollback Skill

## Revert Procedure Based on safe Tags
1. Check safe tags with git log --oneline --decorate
2. Determine target tag (previous safe/task-{n} or safe/baseline)
3. git revert {safe-tag-hash}..HEAD --no-commit
4. git commit -m "revert: security rollback to {safe-tag}"
5. Generate .pipeline/reports/security-report.md

## Strictly Prohibited
- Selective revert at the file level
- Revert to an arbitrary commit without a safe tag
