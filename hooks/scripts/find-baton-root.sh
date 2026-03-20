#!/usr/bin/env bash
# find-baton-root.sh — Project root detection utility for baton
# Usage: source "$SCRIPT_DIR/find-baton-root.sh"
#
# Variables set:
#   BATON_ROOT     - Project root path (exported)
#   BATON_DIR      - .baton directory path
#   BATON_LOG_DIR  - .baton/logs directory path

_baton_debug() {
  if [ "${BATON_DEBUG:-}" = "1" ]; then
    echo "[$(date '+%H:%M:%S')] $*" >> /tmp/baton-debug.log
  fi
}

find_baton_root() {
  local dir="$PWD"

  # 1. Git root with .baton
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -n "$git_root" ] && [ -d "$git_root/.baton" ]; then
    echo "$git_root"
    return 0
  fi

  # 2. Upward search for .baton
  local found_root=""
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.baton" ]; then
      found_root="$dir"
    fi
    dir=$(dirname "$dir")
  done

  if [ -n "$found_root" ]; then
    echo "$found_root"
    return 0
  fi

  # 3. Fallback: Git root
  if [ -n "$git_root" ]; then
    echo "$git_root"
    return 0
  fi

  # 4. Final fallback: PWD
  echo "$PWD"
}

if [ -z "${BATON_ROOT:-}" ]; then
  export BATON_ROOT=$(find_baton_root)
fi

BATON_DIR="$BATON_ROOT/.baton"
BATON_LOG_DIR="$BATON_DIR/logs"

ensure_baton_dirs() {
  mkdir -p "$BATON_LOG_DIR" 2>/dev/null || true
}
