"""ComplexityClassifier — rate an image prompt's visual complexity.

A small structured call, run right after the image prompt is written.
Atomic: it classifies one prompt (the executor / image module owns any
iteration). Its tier selects the image model's quality setting.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template

from schema import Complexity
from src.modules.images.image_models import ImageComplexity
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

COMPLEXITY_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "complexity_classification.md"
)

# Model for the one classification call. A per-call constant, not config:
# the model is a property of this call. Override `classify(model=...)` in
# dev to compare models; production uses this default. Gemma/Gemini route
# on the existing gemini provider key.
COMPLEXITY_MODEL = "gemini/gemini-3.1-flash-lite-preview"


class ComplexityClassifier:
    """The complexity step. ``classify(prompt) -> Complexity``."""

    def __init__(self, *, llm: LLMClient) -> None:
        self._llm = llm

    async def classify(
        self, prompt: str, *, model: str = COMPLEXITY_MODEL
    ) -> Complexity:
        """Classify one image prompt's visual complexity tier."""
        template = COMPLEXITY_PROMPT_PATH.read_text(encoding="utf-8")
        instruction = Template(template).safe_substitute(prompt=prompt)
        result = await self._llm.complete_structured(
            [{"role": "user", "content": instruction}],
            schema=ImageComplexity,
            model=model,
        )
        logger.debug("classified prompt complexity: %s", result.complexity)
        return result.complexity
