"""RunCost — what one pipeline run cost in USD."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class RunCost(BaseModel):
    """The run's total cost plus the per-paid-service breakdown.

    A business figure: the LLM and image buckets are estimated from
    litellm's own model pricing on each response; ``background_removal``
    is a flat per-call rate (PhotoRoom returns no usage). ``llm`` covers
    every structured LLM call (palette, image prompt, complexity, style
    check); ``image_generation`` covers both generation and any
    corrective edit (one service). ``total`` is the sum of the three.
    """

    model_config = ConfigDict(extra="forbid")

    total: float
    llm: float
    image_generation: float
    background_removal: float
