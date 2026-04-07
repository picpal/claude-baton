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
#
# Concurrency model (T3):
#   - All guards that depend on state.json fields (securityHalt, currentTier,
#     currentPhase) are evaluated INSIDE a single python3 block that holds an
#     fcntl.flock(LOCK_EX) on .state.lock for the entire read-decide-write
#     window. This eliminates the read-modify-write race that would otherwise
#     occur if a concurrent state_write changed currentPhase between the
#     bash-level guard reads and the atomic python write.
#   - Guards that do NOT touch state.json (target validation, .agent-stack
#     check) remain in bash for fast rejection without paying the python
#     startup cost.
#   - SLOW_REGRESS=1 environment variable injects a 0.2s sleep inside the
#     locked region to make race-condition tests deterministic.
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
  # This guard does NOT touch state.json — keep it in bash for fast reject.
  local agent_stack_file="$BATON_LOG_DIR/.agent-stack"
  if [ -f "$agent_stack_file" ] && [ -s "$agent_stack_file" ]; then
    echo "[regress_to_phase] SC-REGRESS-01: cannot regress while subagents are active (.agent-stack non-empty)" >&2
    return 4
  fi

  # ----- Guard 2: Validate target against PHASE_ORDER
  # Pure-input validation — does not touch state.json.
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

  # ----- All state-touching guards + atomic mutation happen inside a single
  # locked python block. The python script communicates back via exit codes:
  #   0 — success
  #   1 — generic write/parse failure (treat as error)
  #   2 — Tier-aware refusal
  #   3 — securityHalt is true
  #   5 — deep regression refusal (regressionPending was written)
  #   6 — Done state guard violation
  ensure_baton_dirs
  local stdout_capture
  stdout_capture=$(BATON_STATE_FILE="$STATE_FILE" \
    BATON_TARGET="$target" \
    BATON_FORCE="$force" \
    BATON_REASON="$reason" \
    python3 - <<'PYEOF'
import json, os, sys, tempfile, fcntl
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
target = os.environ['BATON_TARGET']
reason = os.environ['BATON_REASON']
force = os.environ.get('BATON_FORCE', '0') == '1'
lock_path = os.path.join(os.path.dirname(state_file), '.state.lock')

# Phase index maps (must match the bash _regress_phase_index /
# _regress_current_index helpers above).
PHASE_INDEX = {
    'analysis':  1,
    'interview': 2,
    'planning':  3,
    'taskmgr':   4,
    'worker':    5,
    'qa':        6,
    'review':    7,
}
CURRENT_INDEX = {
    'idle':            8,
    'done':            8,
    'issue-register':  0,
    'analysis':        1,
    'interview':       2,
    'planning':        3,
    'taskmgr':         4,
    'worker':          5,
    'qa':              6,
    'review':          7,
}

target_idx = PHASE_INDEX[target]  # already validated by bash caller

# --- BEGIN LOCKED STATE MUTATION (fcntl.flock + atomic os.replace) ---
with open(lock_path, 'w') as lock_fd:
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)

    if os.environ.get('SLOW_REGRESS') == '1':
        import time
        time.sleep(0.2)

    with open(state_file, 'r') as f:
        data = json.load(f)

    # ---------- Guard 3: SC-REGRESS-03 — securityHalt must be false ----------
    if data.get('securityHalt', False) is True:
        sys.stderr.write(
            "[regress_to_phase] SC-REGRESS-03: securityHalt is true; regression refused\n"
        )
        sys.exit(3)

    # ---------- Guard 4: Tier-aware refusal ----------
    tier_val = data.get('currentTier')
    try:
        tier = int(tier_val) if tier_val is not None else None
    except (ValueError, TypeError):
        tier = None

    if tier == 1 and target in ('interview', 'planning', 'taskmgr', 'review'):
        sys.stderr.write(
            "[regress_to_phase] ERROR: Tier 1 pipeline cannot regress to '"
            + target + "' (phase is skipped in Tier 1)\n"
        )
        sys.exit(2)

    # ---------- Guard 5: Done state guard ----------
    current_phase = data.get('currentPhase', 'idle')
    if current_phase == 'done' and target != 'analysis':
        sys.stderr.write(
            "[regress_to_phase] ERROR: pipeline is done; only target='analysis' is allowed (new pipeline pattern)\n"
        )
        sys.exit(6)

    # ---------- Guard 6: SC-REGRESS-04 — deep regression (depth>1) requires --force ----------
    current_idx = CURRENT_INDEX.get(current_phase)
    if current_idx is None:
        # Unknown current phase: be permissive (index 0) to match bash behavior.
        current_idx = 0
    depth = abs(current_idx - target_idx)

    if depth > 1 and not force:
        sys.stderr.write(
            "[regress_to_phase] SC-REGRESS-04: deep regression (depth="
            + str(depth) + " from " + str(current_phase) + " to " + target + ") requires --force\n"
        )
        # Record regressionPending so the caller can re-issue with --force.
        data['regressionPending'] = {
            'target': target,
            'reason': reason,
            'fromPhase': current_phase,
            'depth': depth,
            'timestamp': datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
        }
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
        sys.exit(5)

    # ----- All guards passed — execute the atomic regression. -----

    # Phase ordering and downstream flag map. Order matches PHASE_ORDER:
    # analysis < interview < planning < taskmgr < worker < qa < review.
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

    # ---------- Special: target=analysis -> reset Tier ----------
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
    # regressionTarget activates phase-gate.sh's regression-aware gating —
    # only agents at or before this phase index may spawn during the rework cycle.
    rework['regressionTarget'] = target

    # Capture for the bash-level exec.log line.
    from_phase = current_phase
    attempt_count = rework['attemptCount']

    # ---------- currentPhase update ----------
    data['currentPhase'] = target

    # ---------- regressionHistory append ----------
    now_iso = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    history = data.setdefault('regressionHistory', [])
    history.append({
        'timestamp': now_iso,
        'fromPhase': from_phase if from_phase else 'unknown',
        'toPhase': target,
        'attemptCount': attempt_count,
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

    # Emit a single-line key=value summary on stdout for the bash caller to
    # consume — keeps the python block as the sole writer of state.json while
    # still letting bash append the exec.log line.
    sys.stdout.write(
        "OK from_phase=" + str(from_phase) + " attempt_count=" + str(attempt_count) + "\n"
    )
# --- END LOCKED STATE MUTATION ---
PYEOF
  )
  local rc=$?
  case "$rc" in
    0) ;;  # success — fall through to logging
    2) return 2 ;;  # Tier-aware refusal
    3) return 3 ;;  # securityHalt
    5) return 5 ;;  # deep regression refusal (regressionPending written)
    6) return 6 ;;  # done state guard
    *)
      echo "[regress_to_phase] ERROR: atomic state.json update failed (rc=$rc)" >&2
      return 1
      ;;
  esac

  # ----- Parse python stdout for from_phase / attempt_count -----
  local from_phase="unknown"
  local attempt_count="1"
  if [ -n "$stdout_capture" ]; then
    # Expect: "OK from_phase=<x> attempt_count=<y>"
    local kv
    for kv in $stdout_capture; do
      case "$kv" in
        from_phase=*) from_phase="${kv#from_phase=}" ;;
        attempt_count=*) attempt_count="${kv#attempt_count=}" ;;
      esac
    done
  fi

  # ----- Logging: append to exec.log -----
  local now_iso
  now_iso=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
  echo "[$now_iso] REGRESSION — from=${from_phase:-unknown} to=$target attempt=${attempt_count:-1} reason=\"$reason\"" >> "$BATON_LOG_DIR/exec.log"

  return 0
}
