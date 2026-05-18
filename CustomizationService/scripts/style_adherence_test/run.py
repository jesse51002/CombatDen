"""Run the style-adherence (off-style) vision call across models.

Manual dev script — the style-check sibling of
``image_gen_prompt_test``. Feeds one generated image plus the prompt
that produced it to each model below, printing the ``StyleCheck``
verdict (adherent / reason / edit_instruction) so the off-style
judgement can be compared across models.

Fixture: combatden's ``icon_qrcode`` from run ``20260518T042819Z``
(argv[1] overrides the run id) — a deliberately hard case: image models
render QR-ish grids that rarely match a sculpted-metal brand prompt, so
this should usually come back off-style with a concrete
``edit_instruction``. The prompt is the hand-editable
``test_prompt.md`` sibling; the image is the raw pre-background-removal
PNG (what the production check actually runs on).

Uses the **real** production ``style_adherence.md`` prompt and
``StyleCheck`` schema (and ``STYLE_CHECK_MODEL`` as the first entry) —
testing the actual classification call is the whole point.

Cheap: one vision call per model, no image generation. Needs the chosen
providers' keys in ``.env`` (``GEMINI_API_KEY``, ``ANTHROPIC_API_KEY``).

    poetry run python scripts/style_adherence_test/run.py
    poetry run python scripts/style_adherence_test/run.py 20260518T042819Z
"""

from __future__ import annotations

import asyncio
import base64
import sys
from pathlib import Path
from string import Template

# Standalone entrypoint two levels under the repo root: make `src`/`schema`
# importable regardless of how the venv installed them.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.modules.images.image_models import StyleCheck
from src.modules.images.style_service import (
    PNG_DATA_URL_PREFIX,
    STYLE_CHECK_MODEL,
    STYLE_CHECK_PROMPT_PATH,
)
from src.shared.services.llm_client import LiteLLMClient

PROMPT_PATH = Path(__file__).parent / "test_prompt.md"
APP_DIR = _REPO_ROOT / "apps" / "combatden"
DEFAULT_RUN = "20260518T042819Z"
SLOT = "icon_qrcode"

# Vision models, cheapest → most capable. First is production's
# STYLE_CHECK_MODEL; the others are cross-tier / cross-provider sanity.
MODELS = [
    STYLE_CHECK_MODEL,
]

RULE = "=" * 72


async def main() -> int:
    run = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_RUN
    image = APP_DIR / run / "images" / f"{SLOT}.raw.png"
    if not image.exists():
        raise SystemExit(f"raw image not found: {image}")

    prompt = PROMPT_PATH.read_text(encoding="utf-8").strip()
    template = STYLE_CHECK_PROMPT_PATH.read_text(encoding="utf-8")
    instruction = Template(template).safe_substitute(prompt=prompt)
    encoded = base64.b64encode(image.read_bytes()).decode("ascii")
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": instruction},
                {
                    "type": "image_url",
                    "image_url": {"url": f"{PNG_DATA_URL_PREFIX}{encoded}"},
                },
            ],
        }
    ]

    print(f"image:  {image}")
    print(f"prompt: {prompt}")

    llm = LiteLLMClient()
    for model in MODELS:
        print(f"\n{RULE}\n{model}\n{RULE}")
        try:
            result = await llm.complete_structured(
                messages, schema=StyleCheck, model=model
            )
        except Exception as exc:  # dev tool: report, try the next model
            print(f"FAILED: {exc}")
            continue
        print(f"adherent:        {result.adherent}")
        print(f"reason:          {result.reason}")
        print(f"edit_instruction: {result.edit_instruction}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
