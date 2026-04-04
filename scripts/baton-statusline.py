#!/usr/bin/env python3
"""Render baton pipeline phase progression for Claude Code's statusline.

Output example:
  T2 ●iss━●anl━●itv━●pln━●tsk━◈wrk(3/5)━○qa━○rev
"""

from __future__ import annotations

import json
import os
import sys

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TIER_PHASES = {
    1: ["analysis", "worker", "qa"],
    2: ["issue", "analysis", "interview", "planning", "taskmgr", "worker", "qa", "review"],
    3: ["issue", "analysis", "interview", "planning", "taskmgr", "worker", "qa", "review"],
}

PHASE_ABBREV = {
    "issue": "iss",
    "analysis": "anl",
    "interview": "itv",
    "planning": "pln",
    "taskmgr": "tsk",
    "worker": "wrk",
    "qa": "qa",
    "review": "rev",
}

PHASE_TO_FLAG = {
    "issue": "issueRegistered",
    "analysis": "analysisCompleted",
    "interview": "interviewCompleted",
    "planning": "planningCompleted",
    "taskmgr": "taskMgrCompleted",
    "worker": "workerCompleted",
    "qa": "qaUnitPassed",
    "review": "reviewCompleted",
}

# Normalise currentPhase values that differ from our phase keys.
PHASE_ALIAS = {
    "issue-register": "issue",
}

# ---------------------------------------------------------------------------
# ANSI helpers
# ---------------------------------------------------------------------------

GREEN = "\033[32m"
CYAN_BOLD = "\033[1;36m"
DIM = "\033[2m"
RESET = "\033[0m"


def style(text: str, code: str) -> str:
    """Wrap text with an ANSI code and reset."""
    return f"{code}{text}{RESET}"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _normalise_phase(raw: str) -> str:
    """Map a raw currentPhase value to the canonical phase key."""
    return PHASE_ALIAS.get(raw, raw)


def _is_phase_completed(phase: str, tier: int, phase_flags: dict[str, bool]) -> bool:
    """Return True when the phase should be considered completed."""
    if phase == "qa" and tier in (2, 3):
        return (
            phase_flags.get("qaUnitPassed", False)
            and phase_flags.get("qaIntegrationPassed", False)
        )
    flag_key = PHASE_TO_FLAG.get(phase)
    if flag_key is None:
        return False
    return bool(phase_flags.get(flag_key, False))


def _progress_suffix(phase: str, state: dict[str, object]) -> str:
    """Return a progress count string like '(3/5)' for tracked phases."""
    TRACKER_MAP: dict[str, tuple[str, str | None]] = {
        "worker":   ("workerTracker",   "doneCount"),
        "planning": ("planningTracker", None),
        "review":   ("reviewTracker",   None),
    }
    cfg = TRACKER_MAP.get(phase)
    if not cfg:
        return ""
    tracker = state.get(cfg[0]) or {}
    expected = tracker.get("expected", 0)
    if expected <= 0:
        return ""
    if cfg[1]:  # has direct count field (worker)
        done = tracker.get(cfg[1], 0)
    else:  # uses completed list (planning, review)
        done = len(tracker.get("completed") or [])
    return f"({done}/{expected})"


def _render_phase_token(phase: str, current_phase: str, is_done: bool,
                        tier: int, phase_flags: dict[str, bool],
                        state: dict[str, object]) -> str:
    """Return a styled token for a single pipeline phase."""
    abbrev = PHASE_ABBREV.get(phase, phase)
    if is_done or (_is_phase_completed(phase, tier, phase_flags) and phase != current_phase):
        return style(f"●{abbrev}", GREEN)
    elif phase == current_phase and not is_done:
        progress = _progress_suffix(phase, state)
        return style(f"◈{abbrev}{progress}", CYAN_BOLD)
    else:
        return style(f"○{abbrev}", DIM)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def render_baton_line(project_dir: str) -> str:
    """Return a single statusline string showing pipeline progress.

    Returns "" on any error or when the pipeline is idle / uninitialised.
    """
    try:
        state_path = os.path.join(project_dir, ".baton", "state.json")
        if not os.path.isfile(state_path):
            return ""

        with open(state_path, "r", encoding="utf-8") as fh:
            state = json.load(fh)

        tier = state.get("currentTier")
        raw_phase = state.get("currentPhase", "")
        if raw_phase == "idle":
            return ""

        # Before tier is determined (analysis in progress), show minimal pipeline
        if tier is None:
            if raw_phase in ("analysis", "issue-register"):
                current_phase = _normalise_phase(raw_phase)
                anl_token = style("◈anl", CYAN_BOLD)
                pending = style("━", DIM) + style("○···", DIM)
                return f" T? {anl_token}{pending}"
            return ""

        current_phase = _normalise_phase(raw_phase)
        phase_flags = state.get("phaseFlags") or {}
        phases = TIER_PHASES.get(tier)
        if phases is None:
            return ""

        is_done = raw_phase == "done"

        connector = style("━", DIM)
        tokens = [_render_phase_token(p, current_phase, is_done, tier, phase_flags, state)
                  for p in phases]
        return f" T{tier} {connector.join(tokens)}"

    except Exception:
        return ""


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 baton-statusline.py <project_dir>", file=sys.stderr)
        sys.exit(1)

    line = render_baton_line(sys.argv[1])
    if line:
        print(line)
