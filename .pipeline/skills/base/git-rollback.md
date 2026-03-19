# Git Rollback Skill

## safe 태그 기준 revert 절차
1. git log --oneline --decorate 로 safe 태그 확인
2. 목표 태그 결정 (직전 safe/task-{n} 또는 safe/baseline)
3. git revert {safe-tag-hash}..HEAD --no-commit
4. git commit -m "revert: security rollback to {safe-tag}"
5. .pipeline/reports/security-report.md 생성

## 절대 금지
- 파일 단위 선택적 revert
- safe 태그 없는 임의 커밋으로 revert
