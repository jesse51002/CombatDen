"""RunCost — what one pipeline run cost in USD."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict


class RunCost(BaseModel):
    """The run's total cost, the per-paid-service breakdown, and the same
    spend split per model id.

    A business figure: the LLM and image buckets are estimated from
    litellm's own model pricing on each response; ``background_removal``
    is a flat per-call rate (PhotoRoom returns no usage). ``llm`` covers
    every structured LLM call (palette, image prompt, complexity, style
    check); ``image_generation`` covers both generation and any
    corrective edit (one service); ``icon_generation`` covers Recraft
    SVG generation for any icon slot a curated set couldn't cover.
    ``total`` is the sum of the four.

    ``by_model`` is the same total split by model id (provider prefix
    included), so a run shows exactly what each model spent. The flat-rate
    background remover has no model id, so it appears under a synthetic
    ``"photoroom"`` key; the Recraft icon generator buckets under its own
    model id (e.g. ``"recraftv4_1_utility_vector"``). The buckets are
    disjoint, so ``sum(by_model.values())`` equals ``total`` modulo
    rounding. It
    defaults to ``{}`` for the same back-compat reason ``Output.cost`` is
    optional: an ``output.yaml`` written before this field must still
    validate.
    """

    model_config = ConfigDict(extra="forbid")

    total: float
    llm: float
    image_generation: float
    background_removal: float
    icon_generation: float = 0.0
    by_model: dict[str, float] = {}
