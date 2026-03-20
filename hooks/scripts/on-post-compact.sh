#!/bin/bash
# 컨텍스트 압축 후 핵심 파이프라인 상태 파일 존재 여부 출력

[ -d ".baton" ] || exit 0

echo "[baton] Post-compact: checking pipeline state files..."
for f in .baton/complexity-score.md .baton/todo.md .baton/plan.md; do
  if [ -f "$f" ]; then
    echo "  ✓ $f exists"
  fi
done
