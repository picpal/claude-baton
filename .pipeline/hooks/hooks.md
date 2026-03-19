# Pipeline Hooks — claude-baton

session-init        : Initialize exec.log · Verify .pipeline/ directory

post-analysis       : Save complexity-score.md (including stack detection results)

post-plan           : Save plan.md · [Tier3] git tag safe/baseline

post-task           : Save todo.md (stack auto-tagging complete)

post-work           : Check off completed task in todo.md · draft commit
                      git add {scope-files}
                      git commit -m "feat(task-{id}): {summary}"

unit-qa-pass        : git tag safe/task-{id}
                      Log "QA_PASS task-{id}" to exec.log

integration-qa-pass : git tag safe/integration-{n}

qa-fail             : retry_count++
                      If exceeded 3 retries → Escalate to Main (Task Manager redesign)

post-review         : Save review-report.md

security-halt       : Immediately terminate all running agents
                      Force-log SECURITY_HALT to exec.log
                      Generate .pipeline/reports/security-report.md

rollback-complete   : Create or update security-constraints.md
                      Update lessons.md

pre-spawn           : [1] If security-constraints.md exists, auto-include at the front of the context
                      [2] Read the stack field of the target task from todo.md
                          Load .pipeline/skills/stacks/{stack}/tdd-enforcer.md
                          If that file does not exist, fall back to .pipeline/skills/base/tdd-enforcer.md

post-complete       : Update lessons.md · Print completion notification
