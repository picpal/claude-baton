#!/usr/bin/env bash
# stdin-reader.sh — Shared utility for Claude Code hooks
# All hooks receive data via stdin JSON, not shell arguments or env vars.
#
# Usage: source "$SCRIPT_DIR/stdin-reader.sh"
#
# After sourcing, the following variables are available:
#   HOOK_JSON         - Raw stdin JSON string (cached)
#   HOOK_EVENT        - Hook event name
#   HOOK_TOOL_NAME    - Tool name (e.g., Agent, Bash, Edit)
#   HOOK_TOOL_INPUT   - tool_input as JSON string
#   HOOK_TOOL_RESPONSE - tool_response as JSON string (PostToolUse only)
#   HOOK_SESSION_ID   - Session ID
#
# Function:
#   hook_get_field <jq_path>  - Extract a field using dot notation

# Read stdin once and cache
if [ -z "${HOOK_JSON:-}" ]; then
  HOOK_JSON=$(cat)
fi

_hook_parse_fields() {
  python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    print(d.get('hook_event_name', ''))
    print(d.get('tool_name', ''))
    print(d.get('session_id', ''))
    ti = d.get('tool_input', '')
    if isinstance(ti, dict):
        print(json.dumps(ti, ensure_ascii=False))
    else:
        print(str(ti))
    tr = d.get('tool_response', '')
    if isinstance(tr, dict):
        print(json.dumps(tr, ensure_ascii=False))
    else:
        print(str(tr))
except Exception:
    print('')
    print('')
    print('')
    print('')
    print('')
" "$HOOK_JSON" 2>/dev/null
}

if [ -n "$HOOK_JSON" ]; then
  _parsed=$(_hook_parse_fields)
  HOOK_EVENT=$(echo "$_parsed" | sed -n '1p')
  HOOK_TOOL_NAME=$(echo "$_parsed" | sed -n '2p')
  HOOK_SESSION_ID=$(echo "$_parsed" | sed -n '3p')
  HOOK_TOOL_INPUT=$(echo "$_parsed" | sed -n '4p')
  HOOK_TOOL_RESPONSE=$(echo "$_parsed" | sed -n '5p')
  unset _parsed
else
  HOOK_EVENT=""
  HOOK_TOOL_NAME=""
  HOOK_SESSION_ID=""
  HOOK_TOOL_INPUT=""
  HOOK_TOOL_RESPONSE=""
fi

hook_get_field() {
  local field_path="$1"
  python3 -c "
import sys, json
try:
    d = json.loads(sys.argv[1])
    keys = sys.argv[2].split('.')
    val = d
    for k in keys:
        if isinstance(val, dict):
            val = val.get(k, '')
        else:
            val = ''
            break
    if isinstance(val, dict):
        print(json.dumps(val, ensure_ascii=False))
    else:
        print(str(val) if val else '')
except Exception:
    print('')
" "$HOOK_JSON" "$field_path" 2>/dev/null
}
