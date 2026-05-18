"""Standalone live check for the hardened background-validation prompt.

The smoketest produced a checkmark-on-a-disc *badge* cutout that the old
``background_check.md`` wrongly rejected ("white background around the
circular subject has not been removed"). The disc is part of the composed
subject, not leftover backdrop. This script runs the real validator against
that exact image and asserts it now passes.

Run it (``gemini_api_key`` set in ``.env`` — the validator calls Gemini
directly via litellm):

    poetry run python tests/manual/check_celebration_cutout.py

Exits 0 if the validator returns ``ok=True``, non-zero otherwise. It hits
the live provider on purpose — it tests the *prompt*, which a mock cannot
— so it is deliberately NOT part of the offline ``make test`` suite. For
the full labeled corpus, see ``make test-golden``.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

# Standalone entrypoint: guarantee the repo root is importable regardless of
# how the project venv installed `src` / `schema`.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.modules.images.background_service import (
    BG_VALIDATION_MODEL,
    BackgroundService,
)
from src.shared.services.llm_client import LiteLLMClient

_CUTOUTS = _REPO_ROOT / "tests" / "data" / "cutouts"
BEFORE = _CUTOUTS / "celebration_image.before.png"
AFTER = _CUTOUTS / "celebration_image.cutout.png"


def main() -> int:
    for fixture in (BEFORE, AFTER):
        if not fixture.exists():
            print(f"fixture missing: {fixture}", file=sys.stderr)
            return 2
    verdict = asyncio.run(
        BackgroundService(llm=LiteLLMClient()).validate_cutout(BEFORE, AFTER)
    )
    print(f"model:  {BG_VALIDATION_MODEL}")
    print(f"ok:     {verdict.ok}")
    print(f"reason: {verdict.reason}")
    if verdict.ok:
        print("PASS — hardened prompt accepts the celebration badge cutout.")
        return 0
    print(
        "FAIL — still rejected; the prompt needs more hardening.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
