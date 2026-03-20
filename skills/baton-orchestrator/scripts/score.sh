#!/usr/bin/env bash
# score.sh — Complexity score calculator for claude-baton
# Usage: ./score.sh [options] <file1> <file2> ...
#
# Options:
#   --cross-service    Add +3 for cross-service dependency
#   --new-feature      Add +2 for new feature
#   --architecture     Add +3 for architectural decisions
#   --security         Add +4 for security/auth/payment
#   --db-change        Add +3 for DB schema change
#
# Example:
#   ./score.sh --security --db-change src/AuthService.java src/AuthController.java src/migrations/001.sql

set -euo pipefail

# Parse arguments
CROSS_SERVICE=0
NEW_FEATURE=0
ARCHITECTURE=0
SECURITY=0
DB_CHANGE=0
FILES=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cross-service) CROSS_SERVICE=3; shift ;;
        --new-feature)   NEW_FEATURE=2; shift ;;
        --architecture)  ARCHITECTURE=3; shift ;;
        --security)      SECURITY=4; shift ;;
        --db-change)     DB_CHANGE=3; shift ;;
        --help|-h)
            echo "Usage: $0 [options] <file1> <file2> ..."
            echo ""
            echo "Options:"
            echo "  --cross-service    +3 for cross-service dependency"
            echo "  --new-feature      +2 for new feature"
            echo "  --architecture     +3 for architectural decisions"
            echo "  --security         +4 for security/auth/payment"
            echo "  --db-change        +3 for DB schema change"
            exit 0
            ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *)  FILES+=("$1"); shift ;;
    esac
done

# Calculate file score (1pt per file, max 5)
FILE_COUNT=${#FILES[@]}
if [ "$FILE_COUNT" -gt 5 ]; then
    FILE_SCORE=5
else
    FILE_SCORE=$FILE_COUNT
fi

# Total score
TOTAL=$((FILE_SCORE + CROSS_SERVICE + NEW_FEATURE + ARCHITECTURE + SECURITY + DB_CHANGE))

# Determine tier
if [ "$TOTAL" -le 3 ]; then
    TIER="Tier 1 (Light)"
elif [ "$TOTAL" -le 8 ]; then
    TIER="Tier 2 (Standard)"
else
    TIER="Tier 3 (Full)"
fi

# Output
echo "=== Complexity Score ==="
echo "Files: ${FILE_COUNT} (${FILE_SCORE}pt)"
[ "$CROSS_SERVICE" -gt 0 ] && echo "Cross-service: +${CROSS_SERVICE}"
[ "$NEW_FEATURE" -gt 0 ]   && echo "New feature: +${NEW_FEATURE}"
[ "$ARCHITECTURE" -gt 0 ]  && echo "Architecture: +${ARCHITECTURE}"
[ "$SECURITY" -gt 0 ]      && echo "Security: +${SECURITY}"
[ "$DB_CHANGE" -gt 0 ]     && echo "DB change: +${DB_CHANGE}"
echo "========================"
echo "Total: ${TOTAL}pt → ${TIER}"
