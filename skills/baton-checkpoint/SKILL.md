---
name: baton-checkpoint
description: |
  Checkpoint management skill for saving and restoring named development save points.
  Creates git tags and maintains a .baton/checkpoints.md status file showing all checkpoints.
  Use this skill whenever the user mentions checkpoints, save points, snapshots, restore points,
  or wants to save/bookmark the current state to return to later. Also triggers on:
  체크포인트, 저장점, 복원 지점, 스냅샷, 되돌리기, rollback to a specific point.
  Do NOT use for security rollbacks (use baton:rollback instead) or git operations unrelated to checkpoints.
allowed-tools: Read, Write, Bash, Glob
model: sonnet
---

# Checkpoint Management

Checkpoints are named save points that let the user bookmark a specific state of their project
and return to it later. They combine git tags (for the actual restore capability) with a
human-readable status file (for visibility).

## How Checkpoints Work

A checkpoint is two things:
1. **A git tag** named `checkpoint/<name>` — this is what makes restore possible
2. **An entry in `.baton/checkpoints.md`** — this gives the user a clear overview

The git tag is the source of truth for whether a checkpoint exists.
The md file is the source of truth for descriptions and display order.

## Creating a Checkpoint (save)

```bash
# 1. Check for uncommitted changes
git status --porcelain

# 2. If there are changes, commit them
git add -A
git commit -m "checkpoint: <name>"

# 3. Create the tag at current HEAD
git tag "checkpoint/<name>"

# 4. Update the status file
# (see "Updating the Status File" below)
```

Checkpoint names must be URL-safe: lowercase alphanumeric characters, hyphens, and underscores only.
Reject names with spaces, special characters, or uppercase letters — suggest a corrected version.

## Listing Checkpoints (list)

Read `.baton/checkpoints.md` and display it. If the file doesn't exist or seems stale,
rebuild it from git tags:

```bash
git tag -l 'checkpoint/*' --sort=-creatordate --format='%(refname:short) %(creatordate:short) %(objectname:short)'
```

## Restoring a Checkpoint (restore)

Restoring is a destructive operation — always confirm with the user first.

```bash
# 1. Verify the tag exists
git tag -l "checkpoint/<name>"

# 2. Show what will be reverted
git log --oneline "checkpoint/<name>..HEAD"

# 3. STOP and ask for confirmation — show the commit list above

# 4. Create safety backup
git tag "checkpoint/auto-backup-$(date +%Y%m%d-%H%M%S)"

# 5. Revert (preserve history, never use reset --hard)
git revert "checkpoint/<name>..HEAD" --no-commit
git commit -m "restore: checkpoint/<name> 복원"

# 6. Update status file
```

Why `git revert` instead of `git reset --hard`: revert preserves the full history,
so the user can always see what happened and even undo the restore if needed.

## Deleting a Checkpoint (delete)

```bash
git tag -d "checkpoint/<name>"
# Then update .baton/checkpoints.md
```

## Updating the Status File

After any checkpoint operation, regenerate `.baton/checkpoints.md`:

1. List all checkpoint tags with dates and hashes
2. Read any existing descriptions from the current file (preserve them)
3. Write the updated file in this format:

```markdown
# Checkpoints

| # | Name | Created | Commit | Description |
|---|------|---------|--------|-------------|
| N | name | YYYY-MM-DD HH:MM | abcdef0 | description |

Total: N checkpoints
Latest: <name> (<date>)
```

Order: newest first (descending by creation date).
The `#` column is sequential from total count down to 1.

## Edge Cases

- **No checkpoints exist yet**: Create `.baton/` directory if needed, write empty status file
- **Tag exists but no md entry**: Rebuild the file from tags
- **Md entry exists but tag deleted**: Remove the stale entry
- **Restore with dirty working tree**: Warn the user and ask them to commit or stash first
- **Duplicate name on save**: Reject and suggest appending a number (e.g., `feature-v2`)
