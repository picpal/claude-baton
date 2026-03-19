#!/usr/bin/env bash
# detect-stack.sh — Pre-spawn hook: inject stack skill and security constraints
# Called before agent spawn to ensure correct context

set -euo pipefail

BATON_DIR=".baton"
EVENT="${1:-}"

if [ "$EVENT" = "pre-spawn" ]; then
  # Check if security-constraints.md exists and should be included
  if [ -f "$BATON_DIR/security-constraints.md" ]; then
    echo "[baton] Security constraints detected — will be injected into agent context"
  fi

  # Read stack from todo.md for the current task
  if [ -f "$BATON_DIR/complexity-score.md" ]; then
    echo "[baton] Stack detection results available in complexity-score.md"
  fi
fi
