#!/usr/bin/env bash
# state-manager.sh — Shared utility for reading/writing .baton/state.json
# Usage: source "$SCRIPT_DIR/state-manager.sh"
#
# Functions:
#   state_init        - Create state.json with initial schema if missing
#   state_read        - Read a field (dot notation) from state.json
#   state_write       - Update a field in state.json (auto-updates timestamp)
#   state_get_tier    - Shorthand: read currentTier
#   state_get_phase   - Shorthand: read currentPhase
#   state_set_phase   - Shorthand: update currentPhase
#   state_summary     - Print one-line status summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"

STATE_FILE="$BATON_DIR/state.json"

state_init() {
  if [ -f "$STATE_FILE" ]; then
    return 0
  fi

  ensure_baton_dirs

  BATON_STATE_FILE="$STATE_FILE" python3 -c "
import json, os

state_file = os.environ['BATON_STATE_FILE']

state = {
    'version': 1,
    'currentTier': None,
    'currentPhase': 'idle',
    'phaseFlags': {
        'analysisCompleted': False,
        'interviewCompleted': False,
        'planningCompleted': False,
        'taskMgrCompleted': False,
        'workerCompleted': False,
        'qaUnitPassed': False,
        'qaIntegrationPassed': False,
        'reviewCompleted': False
    },
    'planningTracker': { 'expected': 0, 'completed': [] },
    'reviewTracker': { 'expected': 0, 'completed': [] },
    'workerTracker': { 'expected': 0, 'doneCount': 0 },
    'qaRetryCount': {},
    'reworkStatus': { 'active': False, 'attemptCount': 0 },
    'securityHalt': False,
    'lastSafeTag': None,
    'timestamp': ''
}

os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, 'w') as f:
    json.dump(state, f, indent=2)
    f.write('\n')
" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "[state-manager] state_init failed: could not write $STATE_FILE" >&2
  fi
}

state_read() {
  local field="$1"

  if [ ! -f "$STATE_FILE" ]; then
    state_init 2>/dev/null || true
  fi

  # If state file still doesn't exist after init attempt, return empty
  if [ ! -f "$STATE_FILE" ]; then
    echo ""
    return 0
  fi

  BATON_STATE_FILE="$STATE_FILE" BATON_FIELD="$field" python3 -c "
import json, sys, os

state_file = os.environ['BATON_STATE_FILE']
field = os.environ['BATON_FIELD']

with open(state_file, 'r') as f:
    data = json.load(f)

keys = field.split('.')
val = data
for k in keys:
    if isinstance(val, dict) and k in val:
        val = val[k]
    else:
        print('null')
        sys.exit(0)

if isinstance(val, bool):
    print('true' if val else 'false')
elif val is None:
    print('null')
elif isinstance(val, (dict, list)):
    print(json.dumps(val))
else:
    print(val)
" 2>/dev/null || echo ""
}

state_write() {
  local field="$1"
  local value="$2"

  if [ ! -f "$STATE_FILE" ]; then
    state_init 2>/dev/null || true
  fi

  # If state file still doesn't exist after init attempt, log and return
  if [ ! -f "$STATE_FILE" ]; then
    echo "[state-manager] state_write failed: $STATE_FILE does not exist" >&2
    return 0
  fi

  BATON_STATE_FILE="$STATE_FILE" BATON_FIELD="$field" BATON_VALUE="$value" python3 -c "
import json, sys, os
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
field = os.environ['BATON_FIELD']
value_str = os.environ['BATON_VALUE']

with open(state_file, 'r') as f:
    data = json.load(f)

keys = field.split('.')

# Parse the value
if value_str == 'true':
    parsed = True
elif value_str == 'false':
    parsed = False
elif value_str == 'null':
    parsed = None
else:
    try:
        parsed = json.loads(value_str)
    except (json.JSONDecodeError, ValueError):
        try:
            parsed = int(value_str)
        except ValueError:
            try:
                parsed = float(value_str)
            except ValueError:
                parsed = value_str

# Navigate to the parent and set the value
obj = data
for k in keys[:-1]:
    if k not in obj or not isinstance(obj[k], dict):
        obj[k] = {}
    obj = obj[k]
obj[keys[-1]] = parsed

# Always update timestamp
data['timestamp'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

with open(state_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "[state-manager] state_write failed for field: $field" >&2
  fi
}

state_get_tier() {
  state_read "currentTier"
}

state_get_phase() {
  state_read "currentPhase"
}

state_set_phase() {
  local phase="$1"
  state_write "currentPhase" "$phase"
}

state_summary() {
  if [ ! -f "$STATE_FILE" ]; then
    state_init 2>/dev/null || true
  fi

  # If state file still doesn't exist, return fallback
  if [ ! -f "$STATE_FILE" ]; then
    echo "state: unavailable"
    return 0
  fi

  BATON_STATE_FILE="$STATE_FILE" python3 -c "
import json, os

state_file = os.environ['BATON_STATE_FILE']

with open(state_file, 'r') as f:
    data = json.load(f)

tier = data.get('currentTier', 'null')
phase = data.get('currentPhase', 'idle')
flags = data.get('phaseFlags', {})

def flag(key):
    return 'T' if flags.get(key, False) else 'F'

print(f'Tier: {tier} | Phase: {phase} | Flags: analysis={flag(\"analysisCompleted\")} planning={flag(\"planningCompleted\")} worker={flag(\"workerCompleted\")} qa={flag(\"qaUnitPassed\")} review={flag(\"reviewCompleted\")}')
" 2>/dev/null || echo "state: unavailable"
}
