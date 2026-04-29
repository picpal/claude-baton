#!/bin/bash
# SessionStart hook — fires on startup|resume|clear|compact matchers.
# Reads stdin JSON ({hook_event_name, matcher, ...}) when provided and surfaces
# the lessons.md review reminder + refreshes the statusline module path.

INPUT=""
if [ ! -t 0 ]; then
  INPUT=$(cat)
fi

MATCHER=""
if [ -n "$INPUT" ] && command -v jq >/dev/null 2>&1; then
  MATCHER=$(echo "$INPUT" | jq -r '.matcher // .hook_event_name // empty' 2>/dev/null)
fi

# 1. Lessons review reminder (all matchers)
LESSONS_FILE=".baton/lessons.md"
if [ -f "$LESSONS_FILE" ]; then
  LINES=$(wc -l < "$LESSONS_FILE" | tr -d ' ')
  if [ "$LINES" -gt 0 ]; then
    case "$MATCHER" in
      compact|clear)
        echo "[baton] lessons.md retained ($LINES lines) — review before resuming"
        ;;
      *)
        echo "[baton] lessons.md detected ($LINES lines) — review before proceeding"
        ;;
    esac
  fi
fi

# 2. Statusline module path refresh
STATUSLINE_MODULE="${CLAUDE_PLUGIN_ROOT}/scripts/baton-statusline.py"
if [ -f "$STATUSLINE_MODULE" ]; then
  echo "$STATUSLINE_MODULE" > "${HOME}/.claude/baton-statusline-path.txt"
fi

exit 0
