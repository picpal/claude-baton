#!/usr/bin/env bash
# agent-logger.sh — Track subagent lifecycle for main-guard

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"

[ -d "$BATON_DIR" ] || exit 0

ensure_baton_dirs

AGENT_STACK_FILE="$BATON_LOG_DIR/.agent-stack"
EVENT="${1:-}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

AGENT_NAME=$(hook_get_field "tool_input.description" 2>/dev/null || echo "unknown")

case "$EVENT" in
  start)
    echo "${TIMESTAMP}|${AGENT_NAME}" >> "$AGENT_STACK_FILE"
    ;;
  stop)
    # Remove last line (most recent agent)
    if [ -f "$AGENT_STACK_FILE" ]; then
      sed -i '' '$d' "$AGENT_STACK_FILE" 2>/dev/null || true
      # Clean up empty file
      [ -s "$AGENT_STACK_FILE" ] || rm -f "$AGENT_STACK_FILE"
    fi
    ;;
esac
