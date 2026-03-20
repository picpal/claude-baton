#!/usr/bin/env bash
# detect-stack.sh — Pre-spawn hook: inject stack skill and security constraints
# Called before agent spawn to ensure correct context

BATON_DIR=".baton"
EVENT="${1:-}"

# Skip if .baton doesn't exist yet (pre-init)
[ -d "$BATON_DIR" ] || exit 0

if [ "$EVENT" = "pre-spawn" ]; then
  if [ -f "$BATON_DIR/security-constraints.md" ]; then
    echo "[baton] Security constraints detected — will be injected into agent context"
  fi

  if [ -f "$BATON_DIR/complexity-score.md" ]; then
    echo "[baton] Stack detection results available in complexity-score.md"
  fi
fi
