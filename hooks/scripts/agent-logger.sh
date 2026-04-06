#!/usr/bin/env bash
# agent-logger.sh — Track subagent lifecycle + update state.json on completion
#
# Called by hooks.json:
#   SubagentStart → agent-logger.sh start
#   SubagentStop  → agent-logger.sh stop

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"
source "$SCRIPT_DIR/state-manager.sh"

[ -d "$BATON_DIR" ] || exit 0

ensure_baton_dirs

AGENT_STACK_FILE="$BATON_LOG_DIR/.agent-stack"
EVENT="${1:-}"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# QA_MAX_RETRIES — max QA failures before escalating to taskmgr (default 3)
QA_MAX_RETRIES="${QA_MAX_RETRIES:-3}"

# Get agent name/description — try agent_type first (SubagentStart/Stop actual field),
# then fall back to legacy fields for backward compatibility
AGENT_NAME=$(hook_get_field "agent_type" 2>/dev/null)
if [ -z "$AGENT_NAME" ]; then
  AGENT_NAME=$(hook_get_field "tool_input.description" 2>/dev/null)
fi
if [ -z "$AGENT_NAME" ]; then
  AGENT_NAME=$(hook_get_field "agent_name" 2>/dev/null)
fi
[ -z "$AGENT_NAME" ] && AGENT_NAME="unknown"

# -------------------------------------------------------------------
# Detect agent type from agent_type field or description prefix (case-insensitive)
# Returns: analysis|interview|planning|taskmgr|worker|qa-unit|qa-integration|review|issue-register|unknown
#
# Priority 1: agent_type format (SubagentStart/Stop) — e.g., "claude-baton:security-guardian"
# Priority 2: legacy description-prefix format — e.g., "security guardian:..."
# -------------------------------------------------------------------
detect_agent_type() {
  local desc="$1"
  local lower_desc
  lower_desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]')

  case "$lower_desc" in
    # ------------------------------------------------------------------
    # agent_type format: *:suffix (SubagentStart/SubagentStop JSON field)
    # Matches regardless of prefix (e.g., "claude-baton:worker-agent")
    # ------------------------------------------------------------------
    *:security-guardian)          echo "review" ;;
    *:quality-inspector)          echo "review" ;;
    *:tdd-enforcer-reviewer)      echo "review" ;;
    *:performance-analyst)        echo "review" ;;
    *:standards-keeper)           echo "review" ;;
    *:worker-agent)               echo "worker" ;;
    *:qa-unit)                    echo "qa-unit" ;;
    *:qa-integration)             echo "qa-integration" ;;
    *:analysis-agent)             echo "analysis" ;;
    *:interview-agent)            echo "interview" ;;
    *:planning-architect)         echo "planning" ;;
    *:planning-security)          echo "planning" ;;
    *:planning-dev-lead)          echo "planning" ;;
    *:task-manager)               echo "taskmgr" ;;
    *:issue-register)             echo "issue-register" ;;
    # ------------------------------------------------------------------
    # Legacy description-prefix patterns (backward compatibility)
    # ------------------------------------------------------------------
    analysis:*|analysis\ *)       echo "analysis" ;;
    interview:*)                  echo "interview" ;;
    planning:*|planning-*)        echo "planning" ;;
    taskmgr:*|task\ manager:*)    echo "taskmgr" ;;
    worker:*)                     echo "worker" ;;
    qa-unit:*|qa\ unit:*)         echo "qa-unit" ;;
    qa-integration:*|qa\ integration:*) echo "qa-integration" ;;
    security\ guardian:*)         echo "review" ;;
    quality\ inspector:*)         echo "review" ;;
    tdd\ enforcer:*)              echo "review" ;;
    performance\ analyst:*)       echo "review" ;;
    standards\ keeper:*)          echo "review" ;;
    issue*register*|issue\ register*) echo "issue-register" ;;
    *)                            echo "unknown" ;;
  esac
}

# -------------------------------------------------------------------
# Get agent output text from hook JSON (SubagentStop)
# -------------------------------------------------------------------
get_agent_output() {
  local output
  output=$(hook_get_field "tool_response.content" 2>/dev/null)
  if [ -z "$output" ]; then
    output=$(hook_get_field "tool_response" 2>/dev/null)
  fi
  echo "$output"
}

# -------------------------------------------------------------------
# Auto-advance currentPhase based on phaseFlags and tier
# -------------------------------------------------------------------
update_current_phase() {
  local tier
  tier=$(state_get_tier)

  local issue_done analysis_done planning_done taskmgr_done worker_done
  local qa_unit_done qa_int_done review_done interview_done
  issue_done=$(state_read "phaseFlags.issueRegistered")
  analysis_done=$(state_read "phaseFlags.analysisCompleted")
  interview_done=$(state_read "phaseFlags.interviewCompleted")
  planning_done=$(state_read "phaseFlags.planningCompleted")
  taskmgr_done=$(state_read "phaseFlags.taskMgrCompleted")
  worker_done=$(state_read "phaseFlags.workerCompleted")
  qa_unit_done=$(state_read "phaseFlags.qaUnitPassed")
  qa_int_done=$(state_read "phaseFlags.qaIntegrationPassed")
  review_done=$(state_read "phaseFlags.reviewCompleted")

  local phase="idle"

  if [ "$issue_done" != "true" ] && [ "$tier" != "1" ] && [ "$tier" != "null" ] && [ -n "$tier" ]; then
    phase="issue-register"
  elif [ "$analysis_done" != "true" ]; then
    phase="analysis"
  elif [ "$interview_done" != "true" ] && [ "$tier" != "1" ] && [ "$tier" != "null" ]; then
    phase="interview"
  elif [ "$planning_done" != "true" ] && [ "$tier" != "1" ] && [ "$tier" != "null" ]; then
    phase="planning"
  elif [ "$taskmgr_done" != "true" ] && [ "$tier" != "1" ] && [ "$tier" != "null" ]; then
    phase="taskmgr"
  elif [ "$worker_done" != "true" ]; then
    phase="worker"
  elif [ "$qa_unit_done" != "true" ] || [ "$qa_int_done" != "true" ]; then
    phase="qa"
  elif [ "$review_done" != "true" ] && [ "$tier" != "1" ] && [ "$tier" != "null" ]; then
    phase="review"
  else
    phase="done"
  fi

  state_set_phase "$phase"
}

# -------------------------------------------------------------------
# Add an entry to a JSON array field in state.json
# Uses fcntl.flock + atomic os.replace (same lock convention as
# state-manager.sh) so that parallel calls do not lose appends.
# -------------------------------------------------------------------
state_array_add() {
  local field="$1"
  local value="$2"

  if [ ! -f "$STATE_FILE" ]; then
    state_init
  fi

  BATON_STATE_FILE="$STATE_FILE" BATON_FIELD="$field" BATON_VALUE="$value" python3 -c "
import json, sys, os, tempfile, fcntl
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
field = os.environ['BATON_FIELD']
value = os.environ['BATON_VALUE']
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
    obj = data
    for k in keys[:-1]:
        if k not in obj or not isinstance(obj[k], dict):
            obj[k] = {}
        obj = obj[k]

    last_key = keys[-1]
    if last_key not in obj or not isinstance(obj[last_key], list):
        obj[last_key] = []

    if value not in obj[last_key]:
        obj[last_key].append(value)

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
}

# -------------------------------------------------------------------
# Get length of a JSON array field in state.json
# -------------------------------------------------------------------
state_array_len() {
  local field="$1"
  local raw
  raw=$(state_read "$field")
  if [ "$raw" = "null" ] || [ -z "$raw" ]; then
    echo "0"
    return
  fi
  python3 -c "
import json, sys
try:
    arr = json.loads(sys.argv[1])
    print(len(arr) if isinstance(arr, list) else 0)
except Exception:
    print(0)
" "$raw" 2>/dev/null
}

# -------------------------------------------------------------------
# Increment a numeric field in state.json
# Single locked python block (read+modify+write atomic) — fixes the
# R12 race where the previous bash read-modify-write across two
# subprocesses could lose increments under concurrent calls.
# -------------------------------------------------------------------
state_increment() {
  local field="$1"

  if [ ! -f "$STATE_FILE" ]; then
    state_init
  fi

  BATON_STATE_FILE="$STATE_FILE" BATON_FIELD="$field" python3 -c "
import json, sys, os, tempfile, fcntl
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
field = os.environ['BATON_FIELD']
lock_path = os.path.join(os.path.dirname(state_file), '.state.lock')

# --- BEGIN LOCKED STATE MUTATION (fcntl.flock + atomic os.replace) ---
with open(lock_path, 'w') as lock_fd:
    fcntl.flock(lock_fd.fileno(), fcntl.LOCK_EX)

    if os.environ.get('SLOW_MUTATE') == '1':
        import time
        time.sleep(0.2)

    with open(state_file, 'r') as f:
        data = json.load(f)

    # Navigate dot-notation, creating missing intermediate dicts
    keys = field.split('.')
    obj = data
    for k in keys[:-1]:
        if k not in obj or not isinstance(obj[k], dict):
            obj[k] = {}
        obj = obj[k]

    last_key = keys[-1]
    current = obj.get(last_key, 0)
    if not isinstance(current, (int, float)) or isinstance(current, bool):
        current = 0
    new_val = int(current) + 1
    obj[last_key] = new_val

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

    # Print the new value AFTER the atomic replace, while still holding
    # the lock so callers always see a value consistent with the file.
    print(new_val)
# --- END LOCKED STATE MUTATION ---
" 2>/dev/null
}

# -------------------------------------------------------------------
# Handle analysis agent completion — set tier + expected counts
# -------------------------------------------------------------------
handle_analysis_stop() {
  state_write "phaseFlags.analysisCompleted" "true"

  local output
  output=$(get_agent_output)

  # Parse TIER marker from agent output (e.g., TIER:2)
  local tier=""
  tier=$(echo "$output" | grep -oE 'TIER:[0-9]+' | head -1 | cut -d: -f2)

  if [ -z "$tier" ]; then
    # Fallback: try to detect from complexity-score.md if it exists
    local score_file="$BATON_DIR/../.pipeline/complexity-score.md"
    if [ -f "$score_file" ]; then
      tier=$(grep -oE 'Tier[[:space:]]*[0-9]+' "$score_file" 2>/dev/null | head -1 | grep -oE '[0-9]+')
    fi
  fi

  if [ -n "$tier" ]; then
    state_write "currentTier" "$tier"
    state_write "workerTracker.expected" "1"

    case "$tier" in
      1)
        state_write "planningTracker.expected" "0"
        state_write "reviewTracker.expected" "0"
        # Tier 1 skips: interview, planning, taskmgr, integration QA, review
        local issue_reg
        issue_reg=$(state_read "phaseFlags.issueRegistered")
        if [ "$issue_reg" != "true" ]; then
          state_write "phaseFlags.issueRegistered" "true"
        fi
        state_write "phaseFlags.interviewCompleted" "true"
        state_write "phaseFlags.planningCompleted" "true"
        state_write "phaseFlags.taskMgrCompleted" "true"
        state_write "phaseFlags.qaIntegrationPassed" "true"
        state_write "phaseFlags.reviewCompleted" "true"
        ;;
      2)
        state_write "planningTracker.expected" "1"
        state_write "reviewTracker.expected" "3"
        ;;
      3)
        state_write "planningTracker.expected" "3"
        state_write "reviewTracker.expected" "5"
        ;;
    esac
  fi
}

# -------------------------------------------------------------------
# Handle issue-register agent completion — store issue number
# -------------------------------------------------------------------
handle_issue_register_stop() {
  state_write "phaseFlags.issueRegistered" "true"

  local output
  output=$(get_agent_output)

  local issue_num
  issue_num=$(echo "$output" | grep -oE 'ISSUE_NUMBER:[0-9]+' | head -1 | cut -d: -f2)
  if [ -n "$issue_num" ]; then
    state_write "issueNumber" "$issue_num"
  fi

  local issue_url
  issue_url=$(echo "$output" | grep -oE 'ISSUE_URL:[^ ]+' | head -1 | cut -d: -f2-)
  if [ -n "$issue_url" ]; then
    state_write "issueUrl" "$issue_url"
  fi
}

# -------------------------------------------------------------------
# Handle planning agent completion
# -------------------------------------------------------------------
handle_planning_stop() {
  state_array_add "planningTracker.completed" "$AGENT_NAME"

  local completed_len expected
  completed_len=$(state_array_len "planningTracker.completed")
  expected=$(state_read "planningTracker.expected")

  if [ "$expected" != "null" ] && [ "$expected" != "0" ] && [ "$completed_len" -ge "$expected" ] 2>/dev/null; then
    state_write "phaseFlags.planningCompleted" "true"
  fi
}

# -------------------------------------------------------------------
# Handle task manager completion — set workerTracker.expected from output marker
# -------------------------------------------------------------------
handle_taskmgr_stop() {
  state_write "phaseFlags.taskMgrCompleted" "true"

  local output
  output=$(get_agent_output)

  local count
  count=$(echo "$output" | grep -oE 'WORKER_COUNT:[0-9]+' | head -1 | cut -d: -f2)
  if [ -n "$count" ] && [ "$count" -gt 0 ] 2>/dev/null; then
    state_write "workerTracker.expected" "$count"
  fi
}

# -------------------------------------------------------------------
# Handle worker agent completion
# -------------------------------------------------------------------
handle_worker_stop() {
  local done_count
  done_count=$(state_increment "workerTracker.doneCount")

  local expected
  expected=$(state_read "workerTracker.expected")

  if [ "$expected" != "null" ] && [ "$expected" != "0" ] && [ "$done_count" -ge "$expected" ] 2>/dev/null; then
    state_write "phaseFlags.workerCompleted" "true"
  fi
}

# -------------------------------------------------------------------
# Extract task_id from QA_RESULT marker, defaulting to "global".
# Format: QA_RESULT:(PASS|FAIL|ESCALATED)[:{task-id}]
# Returns task_id via stdout.
# -------------------------------------------------------------------
extract_qa_task_id() {
  local output="$1"
  local raw_marker task_id
  raw_marker=$(echo "$output" | grep -oE 'QA_RESULT:(PASS|FAIL|ESCALATED)(:[a-zA-Z0-9_-]+)?' | head -1)
  task_id=$(echo "$raw_marker" | cut -d: -f3)
  [ -z "$task_id" ] && task_id="global"
  echo "$task_id"
}

# -------------------------------------------------------------------
# Parse QA_RESULT marker from output and update qaRetryCount/qaEscalated
# Format: QA_RESULT:PASS | QA_RESULT:FAIL[:task-id] | QA_RESULT:ESCALATED[:task-id]
#
# Returns the result type (PASS|FAIL|ESCALATED) via stdout
# Side effects: updates qaRetryCount and qaEscalated in state.json
# -------------------------------------------------------------------
handle_qa_result_marker() {
  local output="$1"

  # Match full marker including optional task-id
  local raw_marker
  raw_marker=$(echo "$output" | grep -oE 'QA_RESULT:(PASS|FAIL|ESCALATED)(:[a-zA-Z0-9_-]+)?' | head -1)
  [ -z "$raw_marker" ] && { echo ""; return; }

  # Split on colon: field[0]=QA_RESULT field[1]=result field[2]=task-id (optional)
  local result task_id
  result=$(echo "$raw_marker" | cut -d: -f2)
  task_id=$(echo "$raw_marker" | cut -d: -f3)
  [ -z "$task_id" ] && task_id="global"

  case "$result" in
    PASS)
      # No qaRetryCount update on PASS
      ;;
    FAIL)
      # Increment qaRetryCount.{task-id}
      local current
      current=$(state_read "qaRetryCount.$task_id")
      if [ "$current" = "null" ] || [ -z "$current" ]; then
        current=0
      fi
      local new_count=$(( current + 1 ))
      state_write "qaRetryCount.$task_id" "$new_count"
      ;;
    ESCALATED)
      # Set qaRetryCount.{task-id}=99 and qaEscalated.{task-id}=true
      state_write "qaRetryCount.$task_id" "99"
      state_write "qaEscalated.$task_id" "true"
      ;;
  esac

  echo "$result"
}

# -------------------------------------------------------------------
# Shared QA regression dispatcher — called by handle_qa_unit_stop and
# handle_qa_integration_stop after handle_qa_result_marker returns.
#
# Arguments:
#   $1 — result string: PASS | FAIL | ESCALATED
#   $2 — raw output (used to re-extract task_id)
#
# Dispatches regress_to_phase on FAIL/ESCALATED.
# Logs failure to exec.log but does NOT propagate non-zero exit codes.
#
# NOTE: The .agent-stack pop in the main stop handler (lines above this
# function) runs BEFORE any handle_qa_*_stop call.  By the time this
# function executes, the agent has already been removed from the stack,
# so SC-REGRESS-01 (.agent-stack non-empty guard) will NOT trigger.
# -------------------------------------------------------------------
_dispatch_qa_regression() {
  local result="$1"
  local output="$2"

  case "$result" in
    PASS)
      # No regression on PASS
      return 0
      ;;
    FAIL)
      local task_id
      task_id=$(extract_qa_task_id "$output")

      local retry_count
      retry_count=$(state_read "qaRetryCount.${task_id}")
      retry_count=${retry_count:-0}
      # state_read may return "null" for missing key
      [ "$retry_count" = "null" ] && retry_count=0

      # shellcheck source=/dev/null
      source "$SCRIPT_DIR/regress-to-phase.sh"

      if [ "$retry_count" -ge "$QA_MAX_RETRIES" ]; then
        regress_to_phase "taskmgr" \
          "QA retry exhausted for ${task_id} (count=${retry_count})" \
          "--force" 2>>"$BATON_LOG_DIR/exec.log" || true
      else
        regress_to_phase "worker" \
          "QA failure retry #${retry_count} for ${task_id}" \
          2>>"$BATON_LOG_DIR/exec.log" || true
      fi
      ;;
    ESCALATED)
      local task_id
      task_id=$(extract_qa_task_id "$output")

      # shellcheck source=/dev/null
      source "$SCRIPT_DIR/regress-to-phase.sh"
      regress_to_phase "taskmgr" \
        "QA escalated for ${task_id}" \
        "--force" 2>>"$BATON_LOG_DIR/exec.log" || true
      ;;
  esac
}

# -------------------------------------------------------------------
# Handle QA agent completion — parse QA_RESULT marker
# -------------------------------------------------------------------
handle_qa_unit_stop() {
  local output
  output=$(get_agent_output)

  local result
  result=$(handle_qa_result_marker "$output")

  if [ "$result" = "PASS" ]; then
    state_write "phaseFlags.qaUnitPassed" "true"
  fi

  _dispatch_qa_regression "$result" "$output"
}

handle_qa_integration_stop() {
  local output
  output=$(get_agent_output)

  local result
  result=$(handle_qa_result_marker "$output")

  if [ "$result" = "PASS" ]; then
    state_write "phaseFlags.qaIntegrationPassed" "true"
  fi

  _dispatch_qa_regression "$result" "$output"
}

# -------------------------------------------------------------------
# Activate rework mode if any reviewer reported warnings
# Delegates to regress_to_phase("worker") which atomically resets
# worker/QA/review flags, increments attemptCount, and sets reworkStatus.active=true
#
# NOTE: .agent-stack is already cleared by the stop handler before this
# function is called, so SC-REGRESS-01 will not trigger.
# -------------------------------------------------------------------
activate_rework_if_needed() {
  local has_warnings
  has_warnings=$(state_read "reworkStatus.hasWarnings")
  [ "$has_warnings" != "true" ] && return 0

  # Source regress-to-phase.sh and delegate all state mutations to it.
  # regress_to_phase("worker") atomically:
  #   - resets phaseFlags: workerCompleted, qaUnitPassed, qaIntegrationPassed, reviewCompleted → false
  #   - resets workerTracker.doneCount and workerTracker.expected to 0
  #   - resets reviewTracker.completed to []
  #   - increments reworkStatus.attemptCount
  #   - sets reworkStatus.active=true and reworkStatus.hasWarnings=false
  #   - sets currentPhase="worker"
  # --force is required because review→worker is depth=2 (review=7, worker=5).
  # This is a known automatic internal transition; --force is intentional.
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/regress-to-phase.sh"
  regress_to_phase "worker" "Reviewer reported warnings — auto-rework" "--force"
}

# -------------------------------------------------------------------
# Handle review agent completion
# -------------------------------------------------------------------
handle_review_stop() {
  state_array_add "reviewTracker.completed" "$AGENT_NAME"

  local completed_len expected
  completed_len=$(state_array_len "reviewTracker.completed")
  expected=$(state_read "reviewTracker.expected")

  # Detect warnings in review output
  local output
  output=$(hook_get_field "tool_response.content" 2>/dev/null || echo "")
  if [ -z "$output" ]; then
    output=$(hook_get_field "tool_response" 2>/dev/null || echo "")
  fi
  if echo "$output" | grep -qiE '(WARNING|WARN|경고|개선.?필요|rework.?required)'; then
    state_write "reworkStatus.hasWarnings" "true"
  fi

  if [ "$expected" != "null" ] && [ "$expected" != "0" ] && [ "$completed_len" -ge "$expected" ] 2>/dev/null; then
    state_write "phaseFlags.reviewCompleted" "true"
    # Check if rework needed after all reviewers completed
    activate_rework_if_needed
  fi
}

# ===================================================================
# Main event handler
# ===================================================================
case "$EVENT" in
  start)
    # Reset state when a new analysis agent starts (new pipeline)
    START_AGENT_TYPE=$(detect_agent_type "$AGENT_NAME")
    if [ "$START_AGENT_TYPE" = "analysis" ]; then
      CURRENT_PHASE=$(state_get_phase 2>/dev/null)
      if [ "$CURRENT_PHASE" = "done" ] || [ "$CURRENT_PHASE" = "idle" ]; then
        # Force-reset state.json for fresh pipeline
        rm -f "$STATE_FILE"
        state_init
        state_set_phase "analysis"
      fi
    fi

    # Append to agent stack (existing behavior)
    echo "${TIMESTAMP}|${AGENT_NAME}" >> "$AGENT_STACK_FILE"
    ;;

  stop)
    # Remove last agent from stack (existing behavior)
    if [ -f "$AGENT_STACK_FILE" ]; then
      prune_last_line "$AGENT_STACK_FILE"
      [ -s "$AGENT_STACK_FILE" ] || rm -f "$AGENT_STACK_FILE"
    fi

    # NEW: Update state.json based on agent type
    AGENT_TYPE=$(detect_agent_type "$AGENT_NAME")

    # Ensure state.json exists
    if [ ! -f "$STATE_FILE" ]; then
      state_init
    fi

    case "$AGENT_TYPE" in
      analysis)
        handle_analysis_stop
        ;;
      issue-register)
        handle_issue_register_stop
        ;;
      interview)
        state_write "phaseFlags.interviewCompleted" "true"
        ;;
      planning)
        handle_planning_stop
        ;;
      taskmgr)
        handle_taskmgr_stop
        ;;
      worker)
        handle_worker_stop
        ;;
      qa-unit)
        handle_qa_unit_stop
        ;;
      qa-integration)
        handle_qa_integration_stop
        ;;
      review)
        handle_review_stop
        ;;
      unknown)
        # No state update for unrecognized agents
        ;;
    esac

    # Auto-advance phase after any state update (skip for unknown)
    if [ "$AGENT_TYPE" != "unknown" ]; then
      update_current_phase
    fi
    ;;
esac
