#!/bin/bash
# CLAUDE.md / .baton rules 로드 시 lessons.md 존재 여부 확인 후 안내

# 1. Lessons review reminder
LESSONS_FILE=".baton/lessons.md"
if [ -f "$LESSONS_FILE" ]; then
  LINES=$(wc -l < "$LESSONS_FILE" | tr -d ' ')
  if [ "$LINES" -gt 0 ]; then
    echo "[baton] lessons.md detected ($LINES lines) — review before proceeding"
  fi
fi

# 2. Statusline module path refresh
STATUSLINE_MODULE="${CLAUDE_PLUGIN_ROOT}/scripts/baton-statusline.py"
if [ -f "$STATUSLINE_MODULE" ]; then
  echo "$STATUSLINE_MODULE" > "${HOME}/.claude/baton-statusline-path.txt"
fi
