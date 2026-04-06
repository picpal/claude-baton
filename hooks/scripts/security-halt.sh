#!/usr/bin/env bash
# security-halt.sh — Emergency halt on security issue detection
#
# Purpose:
#   Flag the pipeline as security-halted so that regress_to_phase() and
#   phase-gate.sh refuse to advance until the halt is cleared.
#
# Scope (T4 — this script ONLY handles step 1 of the rollback sequence):
#   1. security-halt.sh   -> sets securityHalt=true  (THIS SCRIPT)
#   2. git revert          (manual or by command)
#   3. User confirms
#   4. Main calls: state_write "securityHalt" "false"
#   5. Main calls: regress_to_phase "planning" "Security rollback"
#
# Usage:
#   security-halt.sh [SEVERITY] [FINDING] [SOURCE_AGENT]
#
# Arguments are optional and captured into state.json securityHaltContext.*
# when provided. Missing arguments are simply not written.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/find-baton-root.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/state-manager.sh"

# Optional positional arguments
SEVERITY="${1:-}"
FINDING="${2:-}"
SOURCE_AGENT="${3:-}"

TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Ensure log/report directories exist regardless of prior pipeline state.
ensure_baton_dirs
mkdir -p "$BATON_DIR/reports"

# Force-log security halt
echo "[${TIMESTAMP}] SECURITY_HALT — Pipeline halted due to security issue" >> "$BATON_LOG_DIR/exec.log"

# ---------------------------------------------------------------
# Primary responsibility: flag state.json securityHalt=true
# state_write auto-initializes state.json via state_init if absent,
# and supports dot notation for nested field creation.
# ---------------------------------------------------------------
state_write "securityHalt" "true"

# Capture optional halt context (severity / finding / source agent / timestamp).
# Nested dot-notation fields are created by state_write on demand — no schema
# migration is required for securityHaltContext.
if [ -n "$SEVERITY" ]; then
  state_write "securityHaltContext.severity" "$SEVERITY"
fi
if [ -n "$FINDING" ]; then
  state_write "securityHaltContext.finding" "$FINDING"
fi
if [ -n "$SOURCE_AGENT" ]; then
  state_write "securityHaltContext.sourceAgent" "$SOURCE_AGENT"
fi
state_write "securityHaltContext.timestamp" "$TIMESTAMP"

# ---------------------------------------------------------------
# Create security report placeholder for the Security Guardian to fill.
# ---------------------------------------------------------------
cat > "$BATON_DIR/reports/security-report.md" << EOF
# Security Report
Generated: ${TIMESTAMP}
Status: HALT
Severity: ${SEVERITY:-<unspecified>}
Source: ${SOURCE_AGENT:-<unspecified>}

## Trigger
Security Guardian declared CRITICAL/HIGH finding.

## Finding
${FINDING:-<!-- Security Guardian will fill this section -->}

## Recovery Sequence
1. Inspect findings above and lastSafeTag in .baton/state.json
2. Execute /baton:rollback (git revert to last safe tag)
3. Confirm the rollback is clean
4. Clear securityHalt: \`state_write "securityHalt" "false"\`
5. Re-enter Planning: \`regress_to_phase "planning" "Security rollback"\`
EOF

echo "[baton] SECURITY HALT executed. Report: $BATON_DIR/reports/security-report.md"
