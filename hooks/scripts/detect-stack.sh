#!/usr/bin/env bash
# detect-stack.sh — Pre-spawn hook: inject stack skill and security constraints
# Called before agent spawn to ensure correct context

BATON_DIR=".baton"
EVENT="${1:-}"

# Skip if .baton doesn't exist yet (pre-init)
[ -d "$BATON_DIR" ] || exit 0

if [ "$EVENT" = "pre-spawn" ]; then
  CONTEXT_PARTS=()
  [ -f "$BATON_DIR/security-constraints.md" ] && CONTEXT_PARTS+=("Security constraints active (.baton/security-constraints.md)")
  [ -f "$BATON_DIR/complexity-score.md" ] && CONTEXT_PARTS+=("Stack detection results in .baton/complexity-score.md")
  if [ ${#CONTEXT_PARTS[@]} -gt 0 ]; then
    CONTEXT=$(printf '%s. ' "${CONTEXT_PARTS[@]}" | sed 's/\. $//')
    jq -n --arg ctx "$CONTEXT" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
      }
    }'
  fi
fi
