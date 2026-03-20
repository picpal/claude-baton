#!/bin/bash
# CLAUDE.md / .baton rules 로드 시 lessons.md 존재 여부 확인 후 안내
LESSONS_FILE=".baton/lessons.md"
if [ -f "$LESSONS_FILE" ]; then
  LINES=$(wc -l < "$LESSONS_FILE" | tr -d ' ')
  if [ "$LINES" -gt 0 ]; then
    echo "[baton] lessons.md detected ($LINES lines) — review before proceeding"
  fi
fi
