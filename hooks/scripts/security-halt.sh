#!/usr/bin/env bash
# security-halt.sh — Emergency halt on security issue detection

set -euo pipefail

BATON_DIR=".baton"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Force-log security halt
echo "[${TIMESTAMP}] SECURITY_HALT — Pipeline halted due to security issue" >> "$BATON_DIR/logs/exec.log"

# Create security report placeholder
mkdir -p "$BATON_DIR/reports"
cat > "$BATON_DIR/reports/security-report.md" << EOF
# Security Report
Generated: ${TIMESTAMP}
Status: HALT

## Trigger
Security Guardian declared CRITICAL/HIGH finding.

## Action Required
1. Review findings below
2. Execute /baton:rollback
3. Re-enter Planning phase

## Findings
<!-- Security Guardian will fill this section -->
EOF

echo "[baton] SECURITY HALT executed. Report: $BATON_DIR/reports/security-report.md"
