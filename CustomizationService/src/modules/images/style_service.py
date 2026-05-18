"""StyleAdherenceService — does the generated image realise its prompt?

A small structured vision call run on the raw generated image, right
before background removal. Atomic: it judges one image against the one
prompt that produced it (the executor / image module owns any
iteration). On a miss its ``edit_instruction`` drives a single
corrective image edit — never a loop.
"""

from __future__ import annotations

import base64
import logging
from pathlib import Path
from string import Template

from src.modules.images.image_models import StyleCheck
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

STYLE_CHECK_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "style_adherence.md"
)
PNG_DATA_URL_PREFIX = "data:image/png;base64,"

# Model for the one style-adherence call. A per-call constant, not config:
# the model is a property of this call. Deliberately the small lite tier —
# this is a conservative yes/no judgement, not a reasoning task. Override
# `check(model=...)` in dev to compare models. Routes on the gemini key.
STYLE_CHECK_MODEL = "gemini/gemini-3.1-flash-lite-preview"


class StyleAdherenceService:
    """The style-adherence step. ``check(image, prompt) -> StyleCheck``."""

    def __init__(self, *, llm: LLMClient) -> None:
        self._llm = llm

    async def check(
        self, image: Path, prompt: str, *, model: str = STYLE_CHECK_MODEL
    ) -> StyleCheck:
        """Judge whether ``image`` realises ``prompt``'s style.

        The only context is the image and the prompt that generated it —
        no brief, palette or slot. Adherent ⇒ ship as-is; otherwise the
        returned ``edit_instruction`` is applied once downstream.
        """
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
                        "image_url": {
                            "url": f"{PNG_DATA_URL_PREFIX}{encoded}"
                        },
                    },
                ],
            }
        ]
        result = await self._llm.complete_structured(
            messages, schema=StyleCheck, model=model
        )
        logger.debug(
            "style adherence: adherent=%s reason=%s",
            result.adherent,
            result.reason,
        )
        return result
