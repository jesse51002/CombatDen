"""Run the image-gen-prompt call across several LLM models, side by side.

Manual dev script. Reads the fully-formed prompt in ``test_prompt.md``
(sibling file — a complete, already-substituted image-prompt-generation
prompt) and sends it to each model below, printing each model's produced
prompt so they can be compared.

``rationale`` has been dropped from production too (shared
``ImagePrompt`` + ``image_prompt_rule.md``). This keeps a local
``_PromptOnly`` schema anyway so the harness stays independent of the
shared model — change it here freely without touching production.

Cheap: this is only the prompt-generation LLM call — it never calls the
image generator. Needs ``ANTHROPIC_API_KEY`` in ``.env``.

    poetry run python scripts/image_gen_prompt_test/run.py
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

from pydantic import BaseModel, ConfigDict, field_validator

# Standalone entrypoint two levels under the repo root: make `src`/`schema`
# importable regardless of how the venv installed them.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.shared.services.llm_client import LiteLLMClient

PROMPT_PATH = Path(__file__).parent / "test_prompt.md"

# Claude tiers, cheapest → most capable. Provider-prefixed for litellm.
MODELS = [
    "anthropic/claude-opus-4-8",
    "anthropic/claude-fable-5",
]

# Models that don't support forced tool use — use raw completion + JSON parse.
NO_STRUCTURED_MODELS = {"anthropic/claude-fable-5"}

RULE = "=" * 72


class _PromptOnly(BaseModel):
    """Prompt-only schema for the no-rationale experiment. Mirrors the
    ``prompt`` field/validation of the shared ``ImagePrompt`` so this is
    an apples-to-apples comparison on the prompt; the shared model is
    intentionally not modified."""

    model_config = ConfigDict(extra="forbid")

    prompt: str

    @field_validator("prompt")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("prompt must be non-empty")
        return v


async def main() -> int:
    prompt = PROMPT_PATH.read_text(encoding="utf-8")
    messages = [{"role": "user", "content": prompt}]
    llm = LiteLLMClient()
    for model in MODELS:
        print(f"\n{RULE}\n{model}\n{RULE}")
        try:
            if model in NO_STRUCTURED_MODELS:
                msg = await llm.complete(messages, model=model)
                content = msg.get("content") or ""
                try:
                    parsed = _PromptOnly.model_validate_json(content)
                    prompt_text = parsed.prompt
                except Exception:
                    prompt_text = content.strip()
            else:
                result = await llm.complete_structured(
                    messages, schema=_PromptOnly, model=model
                )
                prompt_text = result.prompt
        except Exception as exc:  # dev tool: report, try the next model
            print(f"FAILED: {exc}")
            continue
        print("\n--- prompt ---")
        print(prompt_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
