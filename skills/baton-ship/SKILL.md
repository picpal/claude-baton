---
name: baton-ship
description: |-
  Handle the /ship slash command. Route ALL of these to this skill: "/ship", "/ship -m ...", "/ship --dry-run", "ship it". Also handle any user request to push commits to a remote repository, including "push my changes", "commit and push", "push to origin", and Korean equivalents ("올려줘", "푸시해줘", "커밋하고 푸시해", "원격에 올려", "리모트에 푸시해"). This skill replaces the default git commit-and-push workflow with a safer pipeline: Korean commit messages, test execution, and secret detection. Exclude: pull requests, deploys, reverts, diffs, code review.
allowed-tools: Read, Bash, Glob, Grep
model: sonnet
---

# Ship — Commit & Push

Ship stages, commits, and pushes changes to origin in a single workflow.

## Arguments

- `/ship` — commit all changes and push
- `/ship -m "message"` — use the provided message instead of auto-generating
- `/ship --dry-run` — show what would be committed and pushed, but do not execute

Parse arguments from the user's input. If `-m` is provided, skip commit message generation.

## Pre-flight Checks

Run these commands to assess the working tree:

```bash
git status
git diff
git diff --cached
git log --oneline -5
```

1. **No changes at all** (status is clean): Tell the user and stop.
2. **Unstaged changes exist**: Stage all relevant files. Exclude secrets — never stage files matching: `.env`, `*credentials*`, `*secret*`, `*.pem`, `*.key`, `*token*`. If only secret files are found, warn and stop.
3. **Test detection**: Look for test runners in the project:
   - `package.json` → check for `test` script → run `npm test`
   - `pytest.ini`, `pyproject.toml`, `setup.cfg`, or `tests/` dir → run `pytest`
   - `go.mod` → run `go test ./...`
   - `Cargo.toml` → run `cargo test`
   - `build.gradle*` or `pom.xml` → run `./gradlew test` or `mvn test`
   If tests fail, report the failure and stop. Do not commit.

## Commit Message Generation

When no `-m` argument is provided:

0. **Issue reference**: Check if `.baton/issue.md` exists and contains an issue number.
   If yes, append ` (#N)` to the final commit message.
   Format: `type: 한국어 설명 (#123)`

1. Analyze the staged diff (`git diff --cached`) to determine the change type:
   - `feat`: new feature or capability
   - `fix`: bug fix
   - `refactor`: code restructuring without behavior change
   - `chore`: maintenance, dependencies, config
   - `docs`: documentation only
   - `test`: adding or updating tests
   - `style`: formatting, whitespace
2. Write the commit message **in Korean**.
3. Format: `type: 한국어 설명` — 1-2 sentences focusing on "why" not "what".
4. Do **NOT** add `Co-Authored-By` or any trailing tags.
5. Use HEREDOC format:

```bash
git commit -m "$(cat <<'EOF'
type: 한국어 커밋 메시지
EOF
)"
```

## Dry Run Mode

When `--dry-run` is passed:

1. Show which files would be staged
2. Show the generated commit message
3. Show which branch and remote would be pushed to
4. Do NOT execute any git write operations (no add, commit, or push)
5. End with: "Dry run complete. Run `/ship` to execute."

## Push

After a successful commit:

```bash
# Check current branch
BRANCH=$(git symbolic-ref --short HEAD)

# Check if upstream exists
git rev-parse --abbrev-ref @{upstream} 2>/dev/null
```

- If upstream exists: `git push`
- If no upstream: `git push -u origin $BRANCH`

## Safety Rules

- **Never force push.** Do not use `--force` or `--force-with-lease`.
- **Protected branches**: If the current branch is `main` or `master`, you MUST stop and ask a separate, explicit yes/no confirmation question before pushing. The original user command (e.g., "ship it", "/ship", "올려줘") does NOT count as confirmation — treat it only as the trigger to start the workflow. You must print a message like: "You are on the `main` branch. Pushing directly to main is risky. Do you want to proceed? (yes/no)" and then WAIT for the user's reply. Only proceed if the user responds with an explicit affirmative (e.g., "yes", "y"). Any other response — including silence, ambiguity, or "just do it" — means stop.
- **Secret files**: Never commit `.env`, `*credentials*`, `*secret*`, `*.pem`, `*.key`. If detected in the diff, remove them from staging and warn.
- **Push failure**: If push fails (e.g., rejected because remote is ahead), report the error and suggest `git pull --rebase`. Do not auto-resolve.

## Final Report

After a successful ship, display:

```
Shipped!
  Commit : <short-hash> <commit message>
  Branch : <branch-name>
  Remote : <remote-url>
```

If any step failed, display what succeeded and what failed, with actionable next steps.
