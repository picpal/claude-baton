#!/usr/bin/env bash
# regress-to-phase.sh — Phase regression engine for the baton pipeline.
#
# Defines:
#   regress_to_phase TARGET_PHASE REASON [--force]
#
# Resets phaseFlags and trackers from TARGET_PHASE forward, sets currentPhase
# to the target, marks dependent artifacts as stale, appends to
# regressionHistory, and activates rework mode.
#
# Sourcing:
#   source "$SCRIPT_DIR/regress-to-phase.sh"
#
# Exit codes (returned via `return` when sourced):
#   0 — success
#   1 — invalid target phase (not in PHASE_ORDER, or empty)
#   2 — Tier-aware refusal (target invalid for current Tier)
#   3 — SC-REGRESS-03: securityHalt is true
#   4 — SC-REGRESS-01: subagent context (.agent-stack non-empty)
#   5 — SC-REGRESS-04: deep regression (depth>1) requires --force
#   6 — Done state guard violation
#
# Side effects:
#   - Atomic update of $BATON_DIR/state.json (single python3 + os.replace)
#   - Append line to $BATON_DIR/logs/exec.log
#   - May write reworkStatus.regressionPending on SC-REGRESS-04 refusal

# Resolve script directory and source state-manager.sh for state access helpers.
# Use BASH_SOURCE so the path resolves correctly when this file is `source`d.
_REGRESS_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$_REGRESS_SCRIPT_DIR/find-baton-root.sh"
# shellcheck source=/dev/null
source "$_REGRESS_SCRIPT_DIR/state-manager.sh"

# -------------------------------------------------------------------
# Canonical phase ordering. Index = numeric depth from the start.
# Higher index = later in the pipeline.
# Targets restricted to: analysis, interview, planning, taskmgr,
#                        worker, qa, review.
# (issue-register and done are NOT valid regression targets.)
# -------------------------------------------------------------------
_regress_phase_index() {
  case "$1" in
    analysis)  echo 1 ;;
    interview) echo 2 ;;
    planning)  echo 3 ;;
    taskmgr)   echo 4 ;;
    worker)    echo 5 ;;
    qa)        echo 6 ;;
    review)    echo 7 ;;
    *)         echo "" ;;
  esac
}

# Map currentPhase (which may be "done" or "idle") to a numeric index for
# depth comparison. Unknown phases return empty.
_regress_current_index() {
  case "$1" in
    idle|done)        echo 8 ;;  # treat as "after the end" — depth from any target
    issue-register)   echo 0 ;;
    analysis)         echo 1 ;;
    interview)        echo 2 ;;
    planning)         echo 3 ;;
    taskmgr)          echo 4 ;;
    worker)           echo 5 ;;
    qa)               echo 6 ;;
    review)           echo 7 ;;
    *)                echo "" ;;
  esac
}

# -------------------------------------------------------------------
# regress_to_phase TARGET REASON [--force]
# -------------------------------------------------------------------
regress_to_phase() {
  local target="${1:-}"
  local reason="${2:-}"
  local force_flag="${3:-}"
  local force=0
  if [ "$force_flag" = "--force" ]; then
    force=1
  fi

  # ----- Guard 1: SC-REGRESS-01 — subagent context (.agent-stack non-empty)
  local agent_stack_file="$BATON_LOG_DIR/.agent-stack"
  if [ -f "$agent_stack_file" ] && [ -s "$agent_stack_file" ]; then
    echo "[regress_to_phase] SC-REGRESS-01: cannot regress while subagents are active (.agent-stack non-empty)" >&2
    return 4
  fi

  # ----- Guard 2: SC-REGRESS-03 — securityHalt must be false
  local security_halt
  security_halt=$(state_read "securityHalt")
  if [ "$security_halt" = "true" ]; then
    echo "[regress_to_phase] SC-REGRESS-03: securityHalt is true; regression refused" >&2
    return 3
  fi

  # ----- Guard 3: Validate target against PHASE_ORDER
  if [ -z "$target" ]; then
    echo "[regress_to_phase] ERROR: target phase is required" >&2
    return 1
  fi
  local target_idx
  target_idx=$(_regress_phase_index "$target")
  if [ -z "$target_idx" ]; then
    echo "[regress_to_phase] ERROR: invalid target phase '$target' (must be one of: analysis, interview, planning, taskmgr, worker, qa, review)" >&2
    return 1
  fi

  # ----- Guard 4: Tier-aware refusal
  local current_tier
  current_tier=$(state_read "currentTier")
  if [ "$current_tier" = "1" ]; then
    case "$target" in
      interview|planning|taskmgr|review)
        echo "[regress_to_phase] ERROR: Tier 1 pipeline cannot regress to '$target' (phase is skipped in Tier 1)" >&2
        return 2
        ;;
    esac
  fi

  # ----- Guard 5: Done state guard
  local current_phase
  current_phase=$(state_read "currentPhase")
  if [ "$current_phase" = "done" ]; then
    if [ "$target" != "analysis" ]; then
      echo "[regress_to_phase] ERROR: pipeline is done; only target='analysis' is allowed (new pipeline pattern)" >&2
      return 6
    fi
  fi

  # ----- Guard 6: SC-REGRESS-04 — deep regression (depth>1) requires --force
  # Depth is the number of phases between current and target.
  # If currentPhase is done/idle, treat as index 8.
  local current_idx
  current_idx=$(_regress_current_index "$current_phase")
  if [ -z "$current_idx" ]; then
    # Unknown current phase: be permissive (index 0)
    current_idx=0
  fi
  local depth=$((current_idx - target_idx))
  if [ "$depth" -lt 0 ]; then
    depth=$((-depth))
  fi
  if [ "$depth" -gt 1 ] && [ "$force" -eq 0 ]; then
    echo "[regress_to_phase] SC-REGRESS-04: deep regression (depth=$depth from $current_phase to $target) requires --force" >&2
    # Record regressionPending so the caller can re-issue with --force
    BATON_STATE_FILE="$STATE_FILE" \
    BATON_TARGET="$target" \
    BATON_REASON="$reason" \
    BATON_FROM_PHASE="$current_phase" \
    BATON_DEPTH="$depth" \
    python3 - <<'PYEOF' 2>/dev/null || true
import json, os, tempfile
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
target = os.environ['BATON_TARGET']
reason = os.environ['BATON_REASON']
from_phase = os.environ['BATON_FROM_PHASE']
depth = int(os.environ['BATON_DEPTH'])

with open(state_file, 'r') as f:
    data = json.load(f)

data['regressionPending'] = {
    'target': target,
    'reason': reason,
    'fromPhase': from_phase,
    'depth': depth,
    'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
}
data['timestamp'] = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')

dir_name = os.path.dirname(state_file)
with tempfile.NamedTemporaryFile('w', dir=dir_name, delete=False) as tf:
    json.dump(data, tf, indent=2)
    tf.write('\n')
    tmp_path = tf.name
os.replace(tmp_path, state_file)
PYEOF
    return 5
  fi

  # ----- All guards passed — execute the atomic regression.
  # Single python3 + os.replace to keep state.json out of partial states.
  BATON_STATE_FILE="$STATE_FILE" \
  BATON_TARGET="$target" \
  BATON_REASON="$reason" \
  BATON_FROM_PHASE="$current_phase" \
  BATON_TIER="${current_tier:-null}" \
  python3 - <<'PYEOF' 2>/dev/null
import json, os, sys, tempfile
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
target = os.environ['BATON_TARGET']
reason = os.environ['BATON_REASON']
from_phase = os.environ['BATON_FROM_PHASE']
tier_str = os.environ['BATON_TIER']

# Parse tier (may be "null" or empty)
try:
    tier = int(tier_str)
except (ValueError, TypeError):
    tier = None

with open(state_file, 'r') as f:
    data = json.load(f)

# ---------- Phase ordering and downstream flag map ----------
# For each target, list all phaseFlag keys to reset to false (target + downstream).
# Order matches PHASE_ORDER: analysis < interview < planning < taskmgr < worker < qa < review.
DOWNSTREAM = {
    'analysis': [
        'analysisCompleted', 'interviewCompleted', 'planningCompleted',
        'taskMgrCompleted', 'workerCompleted', 'qaUnitPassed',
        'qaIntegrationPassed', 'reviewCompleted',
    ],
    'interview': [
        'interviewCompleted', 'planningCompleted', 'taskMgrCompleted',
        'workerCompleted', 'qaUnitPassed', 'qaIntegrationPassed',
        'reviewCompleted',
    ],
    'planning': [
        'planningCompleted', 'taskMgrCompleted', 'workerCompleted',
        'qaUnitPassed', 'qaIntegrationPassed', 'reviewCompleted',
    ],
    'taskmgr': [
        'taskMgrCompleted', 'workerCompleted', 'qaUnitPassed',
        'qaIntegrationPassed', 'reviewCompleted',
    ],
    'worker': [
        'workerCompleted', 'qaUnitPassed', 'qaIntegrationPassed',
        'reviewCompleted',
    ],
    'qa': [
        'qaUnitPassed', 'qaIntegrationPassed', 'reviewCompleted',
    ],
    'review': [
        'reviewCompleted',
    ],
}

flags = data.setdefault('phaseFlags', {})
for key in DOWNSTREAM[target]:
    flags[key] = False
# issueRegistered is NEVER reset by these targets.

# ---------- Tracker resets ----------
planning_tracker = data.setdefault('planningTracker', {'expected': 0, 'completed': []})
worker_tracker = data.setdefault('workerTracker', {'expected': 0, 'doneCount': 0})
review_tracker = data.setdefault('reviewTracker', {'expected': 0, 'completed': []})

if target in ('analysis', 'interview', 'planning'):
    planning_tracker['completed'] = []
    worker_tracker['doneCount'] = 0
    worker_tracker['expected'] = 0
    review_tracker['completed'] = []
elif target == 'taskmgr':
    worker_tracker['doneCount'] = 0
    worker_tracker['expected'] = 0
    review_tracker['completed'] = []
elif target == 'worker':
    worker_tracker['doneCount'] = 0
    worker_tracker['expected'] = 0
    review_tracker['completed'] = []
elif target == 'qa':
    review_tracker['completed'] = []
elif target == 'review':
    review_tracker['completed'] = []

# ---------- Special: target=analysis -> reset Tier and clear complexity-score from staleness map post-init ----------
if target == 'analysis':
    data['currentTier'] = None

# ---------- Special: Tier 1 + worker target — reactivate skipped flags ----------
if tier == 1 and target == 'worker':
    flags['qaIntegrationPassed'] = True
    flags['reviewCompleted'] = True

# ---------- reworkStatus updates ----------
rework = data.setdefault('reworkStatus', {'active': False, 'attemptCount': 0, 'hasWarnings': False})
rework['active'] = True
rework['attemptCount'] = int(rework.get('attemptCount', 0) or 0) + 1
rework['hasWarnings'] = False

# ---------- currentPhase update ----------
data['currentPhase'] = target

# ---------- regressionHistory append ----------
now_iso = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
history = data.setdefault('regressionHistory', [])
history.append({
    'timestamp': now_iso,
    'fromPhase': from_phase if from_phase else 'unknown',
    'toPhase': target,
    'attemptCount': rework['attemptCount'],
    'reason': reason,
})

# ---------- artifactStale invalidation ----------
stale = data.setdefault('artifactStale', {})
if target == 'analysis':
    stale['complexity-score.md'] = True
    stale['plan.md'] = True
    stale['todo.md'] = True
elif target == 'interview':
    stale['plan.md'] = True
    stale['todo.md'] = True
elif target == 'planning':
    stale['plan.md'] = True
    stale['todo.md'] = True
elif target == 'taskmgr':
    stale['todo.md'] = True
# worker/qa/review: no artifact changes

# ---------- Clear regressionPending on successful regression ----------
if 'regressionPending' in data:
    del data['regressionPending']

# ---------- Update timestamp and write atomically ----------
data['timestamp'] = now_iso

dir_name = os.path.dirname(state_file)
with tempfile.NamedTemporaryFile('w', dir=dir_name, delete=False) as tf:
    json.dump(data, tf, indent=2)
    tf.write('\n')
    tmp_path = tf.name
os.replace(tmp_path, state_file)
PYEOF
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "[regress_to_phase] ERROR: atomic state.json update failed" >&2
    return 1
  fi

  # ----- Logging: append to exec.log
  local attempt_count
  attempt_count=$(state_read "reworkStatus.attemptCount")
  local now_iso
  now_iso=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  ensure_baton_dirs
  echo "[$now_iso] REGRESSION — from=${current_phase:-unknown} to=$target attempt=${attempt_count:-1} reason=\"$reason\"" >> "$BATON_LOG_DIR/exec.log"

  return 0
}
