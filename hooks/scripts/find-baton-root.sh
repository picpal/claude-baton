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
  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)

  # 1. Worktree detection — MUST check before local .baton
  #    In a worktree, .baton/ may exist (tracked files checked out)
  #    but logs/ (gitignored) won't, so state is stale.
  #    Always use the ORIGINAL project's .baton/ for live state.
  local git_common_dir
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
  if [ -n "$git_common_dir" ] && [ "$git_common_dir" != ".git" ] && [ "$git_common_dir" != "$git_root/.git" ]; then
    # git-common-dir returns absolute path to original .git when in worktree
    local original_root
    original_root=$(dirname "$git_common_dir")
    if [ -d "$original_root/.baton" ]; then
      _baton_debug "Worktree detected — using original project: $original_root"
      echo "$original_root"
      return 0
    fi
  fi

  # 2. Git root with .baton
  if [ -n "$git_root" ] && [ -d "$git_root/.baton" ]; then
    echo "$git_root"
    return 0
  fi

  # 3. Upward search for .baton
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

  # 4. Fallback: Git root
  if [ -n "$git_root" ]; then
    echo "$git_root"
    return 0
  fi

  # 5. Final fallback: PWD
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
