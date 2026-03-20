#!/usr/bin/env bash
# log-event.sh — Log pipeline events to exec.log

BATON_DIR=".baton"
EVENT="${1:-unknown}"

# Skip if .baton doesn't exist yet (pre-init)
[ -d "$BATON_DIR" ] || exit 0

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
mkdir -p "$BATON_DIR/logs"
echo "[${TIMESTAMP}] ${EVENT}" >> "$BATON_DIR/logs/exec.log"
