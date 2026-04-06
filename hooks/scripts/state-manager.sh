#!/usr/bin/env bash
# state-manager.sh — Shared utility for reading/writing .baton/state.json
# Usage: source "$SCRIPT_DIR/state-manager.sh"
#
# Functions:
#   state_migrate      - Add missing fields to existing state.json (schema migration)
#   state_init         - Create state.json with initial schema if missing; migrates existing
#   state_read         - Read a field (dot notation) from state.json
#   state_write        - Update a field in state.json (auto-updates timestamp)
#   state_array_len    - Return the length of an array field
#   state_array_clear  - Clear an array field to []
#   state_get_tier     - Shorthand: read currentTier
#   state_get_phase    - Shorthand: read currentPhase
#   state_set_phase    - Shorthand: update currentPhase
#   state_summary      - Print one-line status summary

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"

STATE_FILE="$BATON_DIR/state.json"

state_migrate() {
  if [ ! -f "$STATE_FILE" ]; then
    return 0
  fi

  BATON_STATE_FILE="$STATE_FILE" python3 -c "
import json, os, tempfile, fcntl

state_file = os.environ['BATON_STATE_FILE']
lock_path = os.path.join(os.path.dirname(state_file), '.state.lock')

# --- BEGIN LOCKED STATE MUTATION (fcntl.flock + atomic os.replace) ---
with open(lock_path, 'w') as lock_fd:
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)

    if os.environ.get('SLOW_MUTATE') == '1':
        import time
        time.sleep(0.2)

    with open(state_file, 'r') as f:
        data = json.load(f)

    current_version = data.get('version', 1)
    changed = False

    # Full default schema (version 3)
    default_schema = {
        'version': 3,
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
            'reviewCompleted': False,
            'issueRegistered': False
        },
        'planningTracker': { 'expected': 0, 'completed': [] },
        'reviewTracker': { 'expected': 0, 'completed': [] },
        'workerTracker': { 'expected': 0, 'doneCount': 0 },
        'qaRetryCount': {},
        'reworkStatus': { 'active': False, 'attemptCount': 0, 'hasWarnings': False },
        'regressionHistory': [],
        'artifactStale': {},
        'lastCommitAttemptCount': 0,
        'securityHalt': False,
        'lastSafeTag': None,
        'issueNumber': None,
        'issueUrl': None,
        'issueLabels': [],
        'isExistingIssue': False,
        'timestamp': ''
    }

    # Add missing top-level fields
    for key, default_val in default_schema.items():
        if key == 'version':
            continue
        if key not in data:
            data[key] = default_val
            changed = True

    # Add missing nested fields for dict-type defaults
    for key, default_val in default_schema.items():
        if isinstance(default_val, dict) and key in data and isinstance(data[key], dict):
            for sub_key, sub_default in default_val.items():
                if sub_key not in data[key]:
                    data[key][sub_key] = sub_default
                    changed = True

    # Bump version if schema changed
    if changed or current_version < default_schema['version']:
        data['version'] = default_schema['version']
        changed = True

    if changed:
        dir_name = os.path.dirname(state_file)
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile('w', dir=dir_name, delete=False) as tf:
                json.dump(data, tf, indent=2)
                tf.write('\n')
                tmp_path = tf.name
            os.replace(tmp_path, state_file)
            tmp_path = None
        finally:
            if tmp_path is not None and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
# --- END LOCKED STATE MUTATION ---
" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "[state-manager] state_migrate failed: could not update $STATE_FILE" >&2
  fi
}

state_init() {
  if [ -f "$STATE_FILE" ]; then
    state_migrate
    return 0
  fi

  ensure_baton_dirs

  BATON_STATE_FILE="$STATE_FILE" python3 -c "
import json, os, tempfile, fcntl

state_file = os.environ['BATON_STATE_FILE']
os.makedirs(os.path.dirname(state_file), exist_ok=True)
lock_path = os.path.join(os.path.dirname(state_file), '.state.lock')

# --- BEGIN LOCKED STATE MUTATION (fcntl.flock + atomic os.replace) ---
with open(lock_path, 'w') as lock_fd:
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)

    if os.environ.get('SLOW_MUTATE') == '1':
        import time
        time.sleep(0.2)

    # Re-check inside the lock — another process may have created state.json
    # while we were waiting for the lock. If so, do nothing (the existing
    # state is authoritative; state_migrate handles upgrades on its own path).
    if not os.path.exists(state_file):
        state = {
            'version': 3,
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
                'reviewCompleted': False,
                'issueRegistered': False
            },
            'planningTracker': { 'expected': 0, 'completed': [] },
            'reviewTracker': { 'expected': 0, 'completed': [] },
            'workerTracker': { 'expected': 0, 'doneCount': 0 },
            'qaRetryCount': {},
            'reworkStatus': { 'active': False, 'attemptCount': 0, 'hasWarnings': False },
            'regressionHistory': [],
            'artifactStale': {},
            'lastCommitAttemptCount': 0,
            'securityHalt': False,
            'lastSafeTag': None,
            'issueNumber': None,
            'issueUrl': None,
            'issueLabels': [],
            'isExistingIssue': False,
            'timestamp': ''
        }

        dir_name = os.path.dirname(state_file)
        tmp_path = None
        try:
            with tempfile.NamedTemporaryFile('w', dir=dir_name, delete=False) as tf:
                json.dump(state, tf, indent=2)
                tf.write('\n')
                tmp_path = tf.name
            os.replace(tmp_path, state_file)
            tmp_path = None
        finally:
            if tmp_path is not None and os.path.exists(tmp_path):
                try:
                    os.unlink(tmp_path)
                except OSError:
                    pass
# --- END LOCKED STATE MUTATION ---
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
import json, sys, os, tempfile, fcntl
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
field = os.environ['BATON_FIELD']
value_str = os.environ['BATON_VALUE']
lock_path = os.path.join(os.path.dirname(state_file), '.state.lock')

# --- BEGIN LOCKED STATE MUTATION (fcntl.flock + atomic os.replace) ---
with open(lock_path, 'w') as lock_fd:
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)

    if os.environ.get('SLOW_MUTATE') == '1':
        import time
        time.sleep(0.2)

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

    dir_name = os.path.dirname(state_file)
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile('w', dir=dir_name, delete=False) as tf:
            json.dump(data, tf, indent=2)
            tf.write('\n')
            tmp_path = tf.name
        os.replace(tmp_path, state_file)
        tmp_path = None
    finally:
        if tmp_path is not None and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
# --- END LOCKED STATE MUTATION ---
" 2>/dev/null
  if [ $? -ne 0 ]; then
    echo "[state-manager] state_write failed for field: $field" >&2
  fi
}

state_array_len() {
  local field="$1"

  if [ ! -f "$STATE_FILE" ]; then
    echo "0"
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
        print('0')
        sys.exit(0)

if isinstance(val, list):
    print(len(val))
else:
    print('0')
" 2>/dev/null || echo "0"
}

state_array_clear() {
  local field="$1"
  state_write "$field" "[]"
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

# prune_last_line FILE — removes the last line from FILE portably (POSIX, no sed -i)
prune_last_line() {
  local file="$1"
  [ -f "$file" ] || return 0
  local tmp="${file}.tmp.$$"
  awk 'NR>1{print prev} {prev=$0}' "$file" > "$tmp" && mv "$tmp" "$file"
}

# prune_stale_stack_entries — removes entries with empty AGENT_NAME or older than TTL
# Usage: prune_stale_stack_entries [stack_file]
# Env: STACK_TTL_SECONDS (default 7200 = 2 hours)
# Returns: prints count of removed entries to stdout
prune_stale_stack_entries() {
  local stack_file="${1:-$BATON_LOG_DIR/.agent-stack}"
  [ -f "$stack_file" ] || { echo "0"; return 0; }

  STACK_FILE="$stack_file" \
  STACK_TTL_SECONDS="${STACK_TTL_SECONDS:-7200}" \
  BATON_EXEC_LOG="${BATON_LOG_DIR}/exec.log" \
  python3 - <<'PYEOF'
import os, sys, tempfile
from datetime import datetime, timezone

stack_file = os.environ['STACK_FILE']
ttl = int(os.environ.get('STACK_TTL_SECONDS', 7200))
exec_log = os.environ.get('BATON_EXEC_LOG', '')
now = datetime.now(timezone.utc)

removed = 0
kept = []
removed_entries = []

try:
    with open(stack_file) as fh:
        lines = fh.readlines()
except FileNotFoundError:
    print(0)
    sys.exit(0)

for line in lines:
    line_stripped = line.rstrip('\n')
    if not line_stripped:
        continue

    parts = line_stripped.split('|', 1)
    timestamp_str = parts[0]
    agent_name = parts[1] if len(parts) > 1 else ''

    # Reason 1: empty AGENT_NAME (legacy migration zombies)
    if not agent_name.strip():
        removed += 1
        removed_entries.append((agent_name, timestamp_str, 'empty'))
        continue

    # Reason 2: older than TTL
    try:
        ts = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        age = (now - ts).total_seconds()
        if age > ttl:
            removed += 1
            removed_entries.append((agent_name, timestamp_str, 'ttl'))
            continue
    except (ValueError, TypeError):
        # Unparseable timestamp = zombie
        removed += 1
        removed_entries.append((agent_name, timestamp_str, 'ttl'))
        continue

    kept.append(line)

if removed > 0:
    # Atomic write — same pattern as other state mutators
    dir_name = os.path.dirname(stack_file)
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile('w', dir=dir_name, delete=False) as tf:
            tf.writelines(kept)
            tmp_path = tf.name
        os.replace(tmp_path, stack_file)
        tmp_path = None
    finally:
        if tmp_path is not None and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    # Write STACK_PRUNE log entries for each removed entry
    if exec_log:
        now_str = now.strftime('%Y-%m-%dT%H:%M:%SZ')
        try:
            with open(exec_log, 'a') as log_fh:
                for (entry_agent, entry_ts, reason) in removed_entries:
                    log_fh.write(
                        f'[{now_str}] STACK_PRUNE agent={entry_agent} ts={entry_ts} reason={reason}\n'
                    )
        except OSError:
            pass

print(removed)
PYEOF
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

issue = data.get('issueNumber', None)
issue_str = f'#{issue}' if issue else 'none'
print(f'Tier: {tier} | Phase: {phase} | Issue: {issue_str} | Flags: analysis={flag(\"analysisCompleted\")} planning={flag(\"planningCompleted\")} worker={flag(\"workerCompleted\")} qa={flag(\"qaUnitPassed\")} review={flag(\"reviewCompleted\")}')
" 2>/dev/null || echo "state: unavailable"
}
