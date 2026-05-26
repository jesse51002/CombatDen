"""VerdictReason — why a video is **not** in a company's feed.

Set alongside ``is_good`` by the classification pass to make the not-good cases
self-explanatory instead of overloading a bare ``False``. It is ``None`` when the
video is good — or not yet judged. Serializes as its lowercase value in YAML.
"""

from __future__ import annotations

import enum


class VerdictReason(str, enum.Enum):
    """Why a video was flagged ``is_good=False`` (``None`` when it's good)."""

    # Skipped the quality gate: no transcript to validate, so never sent to the
    # LLM (no classification cost).
    NO_TRANSCRIPT = "no_transcript"
    # The classification call failed after retries (provider or schema error).
    ERRORED_OUT = "errored_out"
    # The LLM judged it off-niche / a match for the brief's avoid_desc.
    LLM_CLASSIFIED_BAD = "llm_classified_bad"
