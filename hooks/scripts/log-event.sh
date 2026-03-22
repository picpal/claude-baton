#!/usr/bin/env bash
# log-event.sh — Log pipeline events to exec.log

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"

EVENT="${1:-unknown}"

# Skip if .baton doesn't exist yet (pre-init)
[ -d "$BATON_DIR" ] || exit 0

ensure_baton_dirs

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
echo "[${TIMESTAMP}] ${EVENT}" >> "$BATON_LOG_DIR/exec.log"
