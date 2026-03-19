---
name: baton:tier
description: Display or override the current Tier level.
---

# /baton:tier

Display or manually override the current Tier level.

## Usage
- `/baton:tier` — Show current Tier and scoring breakdown
- `/baton:tier 2` — Force Tier 2 (for testing)
- `/baton:tier 3` — Force Tier 3 (for testing)

## Rules
- Tier can only be overridden upward (no demotion)
- Override is maintained for the entire session
- Shows scoring breakdown from .baton/complexity-score.md

## Output
```
🎯 Current Tier: {N}

Scoring Breakdown:
  Files to change:     {n}pt
  Cross-service dep:   {+3|0}
  New feature:         {+2|0}
  Arch decision:       {+3|0}
  Security related:    {+4|0}
  DB schema change:    {+3|0}
  ─────────────────
  Total:               {n}pt → Tier {N}
```
