#!/usr/bin/env bash
# phase-gate.sh — PreToolUse hook for Agent matcher
# Checks prerequisites before allowing agent spawn based on Tier + state.json
#
# Exit codes:
#   0 = allow agent spawn
#   2 = block agent spawn (prerequisites not met)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/find-baton-root.sh"
source "$SCRIPT_DIR/stdin-reader.sh"
source "$SCRIPT_DIR/state-manager.sh"

# Skip if .baton doesn't exist (pre-init)
[ -d "$BATON_DIR" ] || exit 0

# -------------------------------------------------------------------
# Detect agent type from description prefix (case-insensitive)
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
    *)                            echo "unknown" ;;
  esac
}

# -------------------------------------------------------------------
# Block helper — prints error to both stdout and stderr, exits 2
# -------------------------------------------------------------------
block() {
  echo "$1" >&2
  echo "$1"
  exit 2
}

# -------------------------------------------------------------------
# Get agent description from hook JSON
# -------------------------------------------------------------------
AGENT_DESC=$(hook_get_field "tool_input.description" 2>/dev/null || echo "")
if [ -z "$AGENT_DESC" ]; then
  # Can't determine agent type — allow by default
  exit 0
fi

AGENT_TYPE=$(detect_agent_type "$AGENT_DESC")

# Unknown agent type — allow (not part of pipeline)
if [ "$AGENT_TYPE" = "unknown" ]; then
  exit 0
fi

# Ensure state.json exists
if [ ! -f "$STATE_FILE" ]; then
  state_init 2>/dev/null || true
fi

# -------------------------------------------------------------------
# Read current state
# -------------------------------------------------------------------
TIER=$(state_get_tier 2>/dev/null || echo "")
PHASE=$(state_get_phase 2>/dev/null || echo "")
SECURITY_HALT=$(state_read "securityHalt" 2>/dev/null || echo "")
REWORK_ACTIVE=$(state_read "reworkStatus.active" 2>/dev/null || echo "")

# If state can't be read, allow (pre-init state)
if [ -z "$TIER" ] && [ -z "$PHASE" ]; then
  exit 0
fi

# -------------------------------------------------------------------
# Global checks
# -------------------------------------------------------------------

# Security halt — block ALL agent spawns
if [ "$SECURITY_HALT" = "true" ]; then
  block "⛔ [Phase Gate] Pipeline halted — Security Rollback in progress"
fi

# Rework mode — bypass all phase-gate checks
if [ "$REWORK_ACTIVE" = "true" ]; then
  exit 0
fi

# phase=done — new pipeline cycle required
if [ "$PHASE" = "done" ]; then
  if [ "$AGENT_TYPE" = "analysis" ]; then
    exit 0  # Allow analysis to start new cycle
  else
    block "⛔ [Phase Gate] Pipeline completed (phase=done). New work requires a fresh pipeline cycle.

Current state:
  Tier: $TIER
  Phase: $PHASE

To start a new task:
  1. State will be reset to idle
  2. Analysis Agent must run first to determine new Tier

Spawn an Analysis Agent to begin a new pipeline cycle."
  fi
fi

# If tier is null/empty (not determined yet), only allow analysis agents
if [ "$TIER" = "null" ] || [ -z "$TIER" ]; then
  if [ "$AGENT_TYPE" = "analysis" ]; then
    exit 0
  else
    block "⛔ [Phase Gate] Prerequisites not met for $AGENT_TYPE

Current state:
  Tier: (not determined)
  Phase: $PHASE
  Missing: Tier determination (analysis must run first)

Required before $AGENT_TYPE:
  - analysisCompleted: false (analysis has not run yet)"
  fi
fi

# -------------------------------------------------------------------
# Tier 1 — block skipped phases
# -------------------------------------------------------------------
if [ "$TIER" = "1" ]; then
  case "$AGENT_TYPE" in
    interview|planning|taskmgr|review)
      block "ℹ️ [Phase Gate] $AGENT_TYPE is skipped for Tier 1"
      ;;
  esac
fi

# -------------------------------------------------------------------
# Read phase flags
# -------------------------------------------------------------------
FLAG_ANALYSIS=$(state_read "phaseFlags.analysisCompleted" 2>/dev/null || echo "")
FLAG_INTERVIEW=$(state_read "phaseFlags.interviewCompleted" 2>/dev/null || echo "")
FLAG_PLANNING=$(state_read "phaseFlags.planningCompleted" 2>/dev/null || echo "")
FLAG_TASKMGR=$(state_read "phaseFlags.taskMgrCompleted" 2>/dev/null || echo "")
FLAG_WORKER=$(state_read "phaseFlags.workerCompleted" 2>/dev/null || echo "")
FLAG_QA_UNIT=$(state_read "phaseFlags.qaUnitPassed" 2>/dev/null || echo "")
FLAG_QA_INT=$(state_read "phaseFlags.qaIntegrationPassed" 2>/dev/null || echo "")
FLAG_REVIEW=$(state_read "phaseFlags.reviewCompleted" 2>/dev/null || echo "")

# -------------------------------------------------------------------
# Build prerequisite check per agent type and tier
# -------------------------------------------------------------------
check_prerequisites() {
  local agent_type="$1"
  local missing=""
  local prereq_lines=""

  case "$agent_type" in
    analysis)
      # No prerequisites for analysis
      return 0
      ;;

    interview)
      # Tier 2/3: no prerequisites (interview comes early)
      return 0
      ;;

    planning)
      # Tier 2/3: requires analysisCompleted
      if [ "$FLAG_ANALYSIS" != "true" ]; then
        missing="analysisCompleted"
        prereq_lines="  - analysisCompleted: $FLAG_ANALYSIS"
      fi
      ;;

    taskmgr)
      # Tier 2/3: requires planningCompleted
      if [ "$FLAG_PLANNING" != "true" ]; then
        missing="planningCompleted"
        prereq_lines="  - planningCompleted: $FLAG_PLANNING"
      fi
      ;;

    worker)
      if [ "$TIER" = "1" ]; then
        # Tier 1: requires analysisCompleted
        if [ "$FLAG_ANALYSIS" != "true" ]; then
          missing="analysisCompleted"
          prereq_lines="  - analysisCompleted: $FLAG_ANALYSIS"
        fi
      else
        # Tier 2/3: requires taskMgrCompleted
        if [ "$FLAG_TASKMGR" != "true" ]; then
          missing="taskMgrCompleted"
          prereq_lines="  - taskMgrCompleted: $FLAG_TASKMGR"
        fi
      fi
      ;;

    qa-unit|qa-integration)
      # All tiers: requires workerCompleted
      if [ "$FLAG_WORKER" != "true" ]; then
        missing="workerCompleted"
        prereq_lines="  - workerCompleted: $FLAG_WORKER"
      fi
      ;;

    review)
      # Tier 2/3: requires qaUnitPassed AND qaIntegrationPassed
      local m=""
      prereq_lines=""
      if [ "$FLAG_QA_UNIT" != "true" ]; then
        m="qaUnitPassed"
        prereq_lines="  - qaUnitPassed: $FLAG_QA_UNIT"
      fi
      if [ "$FLAG_QA_INT" != "true" ]; then
        if [ -n "$m" ]; then
          m="$m, qaIntegrationPassed"
        else
          m="qaIntegrationPassed"
        fi
        prereq_lines="${prereq_lines}
  - qaIntegrationPassed: $FLAG_QA_INT"
      fi
      missing="$m"
      ;;
  esac

  if [ -n "$missing" ]; then
    block "⛔ [Phase Gate] Prerequisites not met for $agent_type

Current state:
  Tier: $TIER
  Phase: $PHASE
  Missing: $missing

Required before $agent_type:
$prereq_lines"
  fi

  return 0
}

check_prerequisites "$AGENT_TYPE"

# All checks passed — allow
exit 0
