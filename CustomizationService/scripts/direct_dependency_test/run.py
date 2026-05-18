"""Run the prompt-build + dependency-usage call across LLM models.

Manual dev script — the dependency-aware sibling of
``image_gen_prompt_test``. Reads the fully-formed prompt in
``test_prompt.md`` (a complete, already-substituted
``image_prompt_rule.md`` for combatden's ``next_rank_belt_image`` with
the injected ``dependency_usage.md`` block listing its ``rank_belt``
dependency) and sends it to each model below, printing both the produced
image ``prompt`` AND the per-dependency ``reference``/``direct`` verdict
so the classification and the prompt can be compared across tiers.

Unlike ``image_gen_prompt_test`` (which keeps a local prompt-only schema
for the no-rationale experiment) this uses the **real shared
``ImagePrompt``** — exercising ``dependency_usage`` is the whole point,
so it must be the production schema, not a mirror.

Cheap: only the prompt-generation LLM call — it never calls the image
generator. Needs ``ANTHROPIC_API_KEY`` in ``.env``.

    poetry run python scripts/direct_dependency_test/run.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

# Standalone entrypoint two levels under the repo root: make `src`/`schema`
# importable regardless of how the venv installed them.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.modules.images.image_models import ImagePrompt
from src.shared.services.llm_client import LiteLLMClient

PROMPT_PATH = Path(__file__).parent / "test_prompt.md"

# Claude tiers, cheapest → most capable. Provider-prefixed for litellm.
# Production writes this prompt with opus; the cheaper tiers are here to
# see whether they classify the dependency as well as they prompt.
MODELS = [
    "anthropic/claude-haiku-4-5-20251001",
    "anthropic/claude-sonnet-4-6",
    "anthropic/claude-opus-4-7",
]

RULE = "=" * 72


async def main() -> int:
    prompt = PROMPT_PATH.read_text(encoding="utf-8")
    messages = [{"role": "user", "content": prompt}]
    llm = LiteLLMClient()
    for model in MODELS:
        print(f"\n{RULE}\n{model}\n{RULE}")
        try:
            result = await llm.complete_structured(
                messages, schema=ImagePrompt, model=model
            )
        except Exception as exc:  # dev tool: report, try the next model
            print(f"FAILED: {exc}")
            continue
        print("\n--- prompt ---")
        print(result.prompt)
        print("\n--- dependency_usage ---")
        if not result.dependency_usage:
            print("(empty)")
        for entry in result.dependency_usage:
            print(f"{entry.dependency}: {entry.usage.value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
