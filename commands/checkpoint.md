---
name: baton:checkpoint
description: |
  Manage development checkpoints — save, list, and restore named save points.
  Use this command to create a snapshot you can return to at any time.
  Triggers: checkpoint, 체크포인트, save point, 저장점, 복원, restore, rollback to point.
---

# /baton:checkpoint

Manage named save points in your development workflow.

## Subcommands

### save \<name\> [description]
Create a new checkpoint with a descriptive name.

```bash
/baton:checkpoint save before-auth-refactor "State before starting auth refactor"
```

**Steps:**
1. Stage all current changes (warn if working tree is dirty with unstaged changes)
2. Create a commit (if there are uncommitted changes): `checkpoint: <name>`
3. Create git tag: `checkpoint/<name>`
4. Update `.baton/checkpoints.md` with the new entry
5. Display the updated checkpoint list

### list
Show all checkpoints with details.

```bash
/baton:checkpoint list
```

Reads `.baton/checkpoints.md` and displays it. If the file is missing, scan for `checkpoint/*` git tags and rebuild it.

### restore \<name\>
Restore the project to a specific checkpoint.

```bash
/baton:checkpoint restore before-auth-refactor
```

**Steps:**
1. Verify the checkpoint tag exists: `git tag -l 'checkpoint/<name>'`
2. Warn the user about what will be lost (show commits since checkpoint)
3. **Wait for explicit user confirmation** before proceeding
4. Create an automatic backup checkpoint: `checkpoint/auto-backup-before-restore-<timestamp>`
5. Execute restore: `git revert <checkpoint-tag>..HEAD --no-commit && git commit`
6. Update `.baton/checkpoints.md`
7. Display result

### delete \<name\>
Remove a checkpoint.

```bash
/baton:checkpoint delete old-checkpoint
```

**Steps:**
1. Remove git tag: `git tag -d checkpoint/<name>`
2. Update `.baton/checkpoints.md`

## Checkpoints Status File

The file `.baton/checkpoints.md` is auto-generated and updated on every checkpoint operation.

### Format
```markdown
# Checkpoints

| # | Name | Created | Commit | Description |
|---|------|---------|--------|-------------|
| 3 | after-api-complete | 2026-03-20 14:30 | a1b2c3d | API implementation complete |
| 2 | before-auth-refactor | 2026-03-20 11:00 | d4e5f6a | Before starting auth refactor |
| 1 | initial-setup | 2026-03-20 09:00 | 7g8h9i0 | Initial project setup complete |

Total: 3 checkpoints
Latest: after-api-complete (2026-03-20 14:30)
```

## Rules
- Checkpoint names must be URL-safe (alphanumeric, hyphens, underscores only)
- Restore always creates a backup checkpoint first (safety net)
- Restore uses `git revert` (not `git reset --hard`) to preserve history
- The `.baton/checkpoints.md` file is the source of truth for descriptions; git tags are the source of truth for existence
