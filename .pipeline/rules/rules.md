# Pipeline Rules — claude-baton

R01 No out-of-phase work   : All agents — Cannot perform work outside their own Phase.
                              On violation, stop immediately and report to Main.

R02 scope-lock              : Worker — Cannot modify files not listed in todo.md.
                              On scope excess, report "SCOPE_EXCEED: {file}" and wait for Main approval.

R03 test-first              : Worker — Tests must be written before implementation code.

R04 Rollback authority      : Only Security Guardian can declare CRITICAL/HIGH Rollback.
                              If another agent discovers a security issue → Report to Main → Request Security Guardian review.

R05 No partial revert       : Main — Security Rollback must be a full batch revert based on the safe tag.
                              Selective per-file revert is prohibited.

R06 Ask Mode                : Forced ON upon entering Tier 3 / upon re-entry after a security Rollback.

R07 No Tier demotion        : Main — An escalated Tier is maintained for the session. Downgrade is not allowed.

R08 CRITICAL/HIGH only      : Security Guardian — MEDIUM and below are handled by the normal rework loop.

R09 safe tag conditions     : Main — safe tags may only be assigned after confirming QA pass.

R10 Conflict escalation     : Main — When a Tier 3 Planning conflict arises (security vs. development),
                              present the trade-offs to the user and request a decision.

R11 No stack assumptions    : Analysis agent — Never assume the tech stack.
                              Must read and confirm from build files (package.json, build.gradle, etc.).
                              On detection failure, report to Main and request confirmation from the user.

R12 Multi-stack task split  : Task Manager — If a single task spans two stacks,
                              it must be split into separate tasks per stack.
