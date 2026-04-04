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

# Get agent name/description — try agent_name first (SubagentStart/Stop), then tool_input.description
AGENT_NAME=$(hook_get_field "agent_name" 2>/dev/null)
if [ -z "$AGENT_NAME" ]; then
  AGENT_NAME=$(hook_get_field "tool_input.description" 2>/dev/null || echo "unknown")
fi

# -------------------------------------------------------------------
# Detect agent type from description prefix (case-insensitive check)
# Returns: analysis|interview|planning|taskmgr|worker|qa-unit|qa-integration|review|unknown
# -------------------------------------------------------------------
detect_agent_type() {
  local desc="$1"
  local lower_desc
  lower_desc=$(echo "$desc" | tr '[:upper:]' '[:lower:]')

  case "$lower_desc" in
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
# -------------------------------------------------------------------
state_array_add() {
  local field="$1"
  local value="$2"

  if [ ! -f "$STATE_FILE" ]; then
    state_init
  fi

  BATON_STATE_FILE="$STATE_FILE" BATON_FIELD="$field" BATON_VALUE="$value" python3 -c "
import json, sys, os
from datetime import datetime, timezone

state_file = os.environ['BATON_STATE_FILE']
field = os.environ['BATON_FIELD']
value = os.environ['BATON_VALUE']

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

with open(state_file, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
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
# -------------------------------------------------------------------
state_increment() {
  local field="$1"
  local current
  current=$(state_read "$field")
  if [ "$current" = "null" ] || [ -z "$current" ]; then
    current=0
  fi
  local new_val=$((current + 1))
  state_write "$field" "$new_val"
  echo "$new_val"
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
# Handle QA agent completion — parse QA_RESULT marker
# -------------------------------------------------------------------
handle_qa_unit_stop() {
  local output
  output=$(get_agent_output)

  local result
  result=$(echo "$output" | grep -oE 'QA_RESULT:(PASS|FAIL)' | head -1 | cut -d: -f2)

  if [ "$result" = "PASS" ]; then
    state_write "phaseFlags.qaUnitPassed" "true"
  fi
}

handle_qa_integration_stop() {
  local output
  output=$(get_agent_output)

  local result
  result=$(echo "$output" | grep -oE 'QA_RESULT:(PASS|FAIL)' | head -1 | cut -d: -f2)

  if [ "$result" = "PASS" ]; then
    state_write "phaseFlags.qaIntegrationPassed" "true"
  fi
}

# -------------------------------------------------------------------
# Handle review agent completion
# -------------------------------------------------------------------
handle_review_stop() {
  state_array_add "reviewTracker.completed" "$AGENT_NAME"

  local completed_len expected
  completed_len=$(state_array_len "reviewTracker.completed")
  expected=$(state_read "reviewTracker.expected")

  if [ "$expected" != "null" ] && [ "$expected" != "0" ] && [ "$completed_len" -ge "$expected" ] 2>/dev/null; then
    state_write "phaseFlags.reviewCompleted" "true"
  fi
}

# ===================================================================
# Main event handler
# ===================================================================
case "$EVENT" in
  start)
    # Append to agent stack (existing behavior)
    echo "${TIMESTAMP}|${AGENT_NAME}" >> "$AGENT_STACK_FILE"
    ;;

  stop)
    # Remove last agent from stack (existing behavior)
    if [ -f "$AGENT_STACK_FILE" ]; then
      sed -i '' '$d' "$AGENT_STACK_FILE" 2>/dev/null || true
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
        state_write "phaseFlags.taskMgrCompleted" "true"
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
