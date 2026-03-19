#!/usr/bin/env bash
# safe-tag.sh — Create safe tags after QA passes
# Usage: safe-tag.sh task <task-id> | integration <n> | baseline

set -euo pipefail

TAG_TYPE="${1:-}"
TAG_ID="${2:-}"

case "$TAG_TYPE" in
  task)
    git tag "safe/task-${TAG_ID}"
    echo "[baton] Created tag: safe/task-${TAG_ID}"
    ;;
  integration)
    git tag "safe/integration-${TAG_ID}"
    echo "[baton] Created tag: safe/integration-${TAG_ID}"
    ;;
  baseline)
    git tag "safe/baseline"
    echo "[baton] Created tag: safe/baseline"
    ;;
  *)
    echo "[baton] Error: Unknown tag type '${TAG_TYPE}'"
    echo "Usage: safe-tag.sh task <id> | integration <n> | baseline"
    exit 1
    ;;
esac
