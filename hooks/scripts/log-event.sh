#!/usr/bin/env bash
# log-event.sh — Enriched pipeline event logging to exec.log
#
# Usage:
#   log-event.sh <event_tag>   (stdin: hook JSON payload for post-tool events)
#
# For post-tool events: sources stdin-reader.sh to extract exit_code + cmd.
# Writes:  [ISO_TS] POST_BASH exit=N cmd="<truncated_80>"
# Noise suppression: skip if exit=0 AND cmd is read-only pattern AND no > in cmd.
#
# For worktree-* events: writes [ISO_TS] <event_tag> unchanged.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"

EVENT="${1:-unknown}"

# Skip if .baton doesn't exist yet (pre-init)
[ -d "$BATON_DIR" ] || exit 0

ensure_baton_dirs

LOG_FILE="$BATON_LOG_DIR/exec.log"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# ── post-tool: structured POST_BASH schema ────────────────────────────────────
if [ "$EVENT" = "post-tool" ]; then
  # Read stdin once (may be empty when no hook payload available)
  HOOK_JSON=""
  if [ ! -t 0 ]; then
    HOOK_JSON=$(cat)
  fi

  EXIT_CODE=""
  CMD=""

  if [ -n "$HOOK_JSON" ]; then
    # Extract exit_code and cmd via python3 (same pattern as stdin-reader.sh)
    _parsed=$(python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    tr = d.get('tool_response', {})
    ti = d.get('tool_input', {})
    exit_code = tr.get('exit_code', '') if isinstance(tr, dict) else ''
    cmd = ti.get('command', '') if isinstance(ti, dict) else ''
    print(exit_code)
    print(cmd)
except Exception:
    print('')
    print('')
" "$HOOK_JSON" 2>/dev/null || printf '\n')
    EXIT_CODE=$(echo "$_parsed" | sed -n '1p')
    CMD=$(echo "$_parsed" | sed -n '2p')
    unset _parsed
  fi

  # Default exit_code to 0 if missing/empty
  if [ -z "$EXIT_CODE" ]; then
    EXIT_CODE="0"
  fi

  # Noise suppression: skip if exit=0 AND read-only cmd pattern AND no > redirect
  if [ "$EXIT_CODE" = "0" ]; then
    # Strip leading whitespace to check first token
    _cmd_trimmed="${CMD#"${CMD%%[![:space:]]*}"}"
    _first_token="${_cmd_trimmed%% *}"
    _is_readonly=0
    case "$_first_token" in
      cat|ls|grep|find|jq|wc|head|tail)
        _is_readonly=1
        ;;
      python3)
        # python3 -c only: check if second token is -c
        _second="${_cmd_trimmed#* }"
        _second_token="${_second%% *}"
        if [ "$_second_token" = "-c" ]; then
          _is_readonly=1
        fi
        ;;
    esac

    if [ "$_is_readonly" = "1" ]; then
      # Check for redirect character >
      case "$CMD" in
        *">"*)
          # Has redirect — NOT suppressed
          ;;
        *)
          # Pure read-only, no redirect — suppress
          exit 0
          ;;
      esac
    fi
  fi

  # Truncate cmd to 80 characters
  CMD_TRUNCATED=$(echo "$CMD" | cut -c1-80)

  LOG_LINE="[$TIMESTAMP] POST_BASH exit=$EXIT_CODE cmd=\"$CMD_TRUNCATED\""
  echo "$LOG_LINE" >> "$LOG_FILE"
  echo "$LOG_LINE"
  exit 0
fi

# ── worktree and other events: unchanged format ───────────────────────────────
LOG_LINE="[$TIMESTAMP] $EVENT"
echo "$LOG_LINE" >> "$LOG_FILE"
echo "$LOG_LINE"
