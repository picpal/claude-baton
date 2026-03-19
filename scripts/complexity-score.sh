#!/usr/bin/env bash
# complexity-score.sh — Helper to compute complexity score
# Reads .baton/complexity-score.md and outputs the current tier

set -euo pipefail

BATON_DIR=".baton"
SCORE_FILE="$BATON_DIR/complexity-score.md"

if [ ! -f "$SCORE_FILE" ]; then
  echo "[baton] No complexity-score.md found. Run analysis first."
  exit 1
fi

# Extract total score line
TOTAL=$(grep -oP 'Total:\s*\K\d+' "$SCORE_FILE" 2>/dev/null || echo "0")

if [ "$TOTAL" -le 3 ]; then
  TIER=1
elif [ "$TOTAL" -le 8 ]; then
  TIER=2
else
  TIER=3
fi

echo "Score: ${TOTAL}pt → Tier ${TIER}"
