#!/usr/bin/env bash
# log-event.sh — Log pipeline events to exec.log

set -euo pipefail

BATON_DIR=".baton"
EVENT="${1:-unknown}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Ensure log directory exists
mkdir -p "$BATON_DIR/logs"

# Log the event
echo "[${TIMESTAMP}] ${EVENT}" >> "$BATON_DIR/logs/exec.log"
