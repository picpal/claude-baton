#!/usr/bin/env bash
# on-stop-failure.sh — Safe agent-stack pop on StopFailure hook event
#
# Reads stdin JSON to extract agent_type of the failing agent.
# If agent_type found: searches .agent-stack LIFO for last matching entry
#   and removes ONLY that line atomically via python3.
# If agent_type NOT found or not in stack: logs warning, leaves stack intact.
# Always logs STOP_FAILURE event to exec.log.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/state-manager.sh"

[ -d "$BATON_DIR" ] || exit 0

ensure_baton_dirs

LOG_FILE="$BATON_LOG_DIR/exec.log"
STACK_FILE="$BATON_LOG_DIR/.agent-stack"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Read stdin once (non-blocking; skip if no data)
HOOK_INPUT=""
if [ ! -t 0 ]; then
  HOOK_INPUT="$(cat)"
fi

# Extract agent_type from payload
AGENT_TYPE=""
if [ -n "$HOOK_INPUT" ]; then
  AGENT_TYPE=$(echo "$HOOK_INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Try direct agent_type first, then nested subagent_type
    val = d.get('agent_type', '') or d.get('tool_input', {}).get('subagent_type', '')
    print(val if val else '')
except Exception:
    print('')
" 2>/dev/null || echo "")
fi

# Always log the STOP_FAILURE event
echo "[$TS] STOP_FAILURE | agent=$AGENT_TYPE | reason=api_error" >> "$LOG_FILE"

if [ -n "$AGENT_TYPE" ] && [ -f "$STACK_FILE" ]; then
  # Search LIFO for last matching entry and remove it atomically
  # Use || rc=... to capture exit code without triggering set -e
  rc=0
  STACK_FILE="$STACK_FILE" AGENT_TYPE="$AGENT_TYPE" python3 - <<'PYEOF' || rc=$?
import os, sys, tempfile

stack_file = os.environ['STACK_FILE']
target_type = os.environ['AGENT_TYPE']

try:
    with open(stack_file) as fh:
        lines = fh.readlines()
except FileNotFoundError:
    sys.exit(0)

# LIFO: search from end to find last matching entry
removed_idx = None
for i in range(len(lines) - 1, -1, -1):
    parts = lines[i].rstrip('\n').split('|', 1)
    if len(parts) > 1 and parts[1].strip() == target_type:
        removed_idx = i
        break

if removed_idx is None:
    sys.exit(2)  # not found — caller checks rc

new_lines = lines[:removed_idx] + lines[removed_idx + 1:]

# Atomic write: temp file in same dir, then os.replace
dir_name = os.path.dirname(stack_file)
tmp_path = None
try:
    with tempfile.NamedTemporaryFile('w', dir=dir_name, delete=False) as tf:
        tf.writelines(new_lines)
        tmp_path = tf.name
    os.replace(tmp_path, stack_file)
    tmp_path = None
finally:
    if tmp_path is not None and os.path.exists(tmp_path):
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
PYEOF
  if [ "$rc" -eq 0 ]; then
    echo "[$TS] STACK_POP | agent=$AGENT_TYPE | reason=stop_failure" >> "$LOG_FILE"
  elif [ "$rc" -eq 2 ]; then
    echo "[$TS] STOP_FAILURE_WARNING | agent=$AGENT_TYPE | reason=not_in_stack" >> "$LOG_FILE"
  fi
elif [ -z "$AGENT_TYPE" ]; then
  echo "[$TS] STOP_FAILURE_WARNING | reason=no_agent_type_in_payload | stack_left_intact" >> "$LOG_FILE"
fi

exit 0
