#!/usr/bin/env bash
# PreCompact hook — snapshot critical .baton state files before context compaction
# so that post-compact recovery can diff against the pre-compact baseline.
# Non-blocking: always exits 0.

set -u

[ -d ".baton" ] || exit 0

TS=$(date +%s)
SNAP_DIR=".baton/snapshots/pre-compact-${TS}"
mkdir -p "$SNAP_DIR" 2>/dev/null || exit 0

for f in .baton/state.json .baton/lessons.md; do
  if [ -f "$f" ]; then
    cp -p "$f" "$SNAP_DIR/" 2>/dev/null || true
  fi
done

echo "[baton] pre-compact snapshot → $SNAP_DIR"
exit 0
