"""Per-call USD cost via litellm's own pricing, plus a running-cost mixin.

Cost always comes from litellm's own model pricing — there is no
hand-maintained price table to drift out of date.

- **Chat / LLM calls:** ``litellm.completion_cost`` prices these directly
  (verified for the provider-prefixed ids the modules pass:
  ``anthropic/claude-opus-4-7``, ``anthropic/claude-haiku-4-5-...``,
  ``gemini/gemini-3.1-flash-lite-preview``).
- **Image calls:** ``litellm.completion_cost`` mis-routes token-priced
  image models (``openai/gpt-image-2``) to its old size-keyed pricing and
  raises ``No pricing information``. litellm *does* ship the correct
  calculation — ``calculate_image_response_cost_from_usage`` (it calls
  ``get_model_info`` internally) — but only wires it for Gemini/Vertex,
  not OpenAI. So for image responses we call that helper ourselves.

A call litellm still cannot price (no usage on the response, ``0`` /
``None`` / it raises) is counted as ``$0.0`` **and logged at warning with
the raw usage + hidden params** — a zero must be visible and diagnosable,
never silent. This is a guard, not a fallback price source.
"""

from __future__ import annotations

import logging
from typing import Any

import litellm
from litellm import ImageResponse

logger = logging.getLogger(__name__)


def _image_cost_from_usage(resp: ImageResponse, model: str) -> float | None:
    """litellm's own usage→cost calc for token-priced image models.

    Uses ``get_model_info`` prices internally. Returns ``None`` when the
    response carries no usable usage (then the caller logs + counts $0).
    The helper is an internal litellm symbol, so the import is defensive:
    a future litellm refactor degrades to the $0 guard, never a crash.
    """
    try:
        from litellm.litellm_core_utils.llm_cost_calc.utils import (
            calculate_image_response_cost_from_usage,
        )

        provider = litellm.get_llm_provider(model)[1]
        cost = calculate_image_response_cost_from_usage(
            model=model,
            image_response=resp,
            custom_llm_provider=provider,
        )
        return None if cost is None else float(cost)
    except Exception as exc:  # noqa: BLE001 — any failure ⇒ caller guards
        logger.debug("image usage cost calc failed for %s: %s", model, exc)
        return None


def litellm_call_cost(resp: Any, model: str) -> float:
    """USD for one litellm response via litellm's own model pricing.

    Never raises: an unpriceable call is ``0.0`` with a warning (carrying
    the raw usage) so the accumulating total cannot be derailed, and a
    zero is diagnosable rather than silent.
    """
    completion_cost_err: Exception | None = None
    try:
        cost = litellm.completion_cost(completion_response=resp, model=model)
        if cost:
            return float(cost)
    except Exception as exc:  # noqa: BLE001 — try the image path next
        completion_cost_err = exc

    # Image models: litellm's completion_cost can't price token-based
    # image gen; its own usage-based helper can (when usage is present).
    if isinstance(resp, ImageResponse):
        img_cost = _image_cost_from_usage(resp, model)
        if img_cost:
            return img_cost
        logger.warning(
            "litellm could not price image call %s (completion_cost: %s); "
            "usage=%r hidden=%r — counting $0",
            model,
            completion_cost_err,
            getattr(resp, "usage", None),
            getattr(resp, "_hidden_params", None),
        )
        return 0.0

    logger.warning(
        "litellm returned no cost for a %s call (%s) — counting $0",
        model,
        completion_cost_err,
    )
    return 0.0


class CostTracking:
    """Mixin: a per-instance running USD total a paid service accumulates,
    plus the same spend split per model id.

    Lazy by design — no ``__init__`` so it composes onto the existing
    services without touching their construction or MRO. The writer reads
    ``cost`` (the running total) and ``cost_by_model`` (the per-model-id
    split) off each service to assemble the run's ``RunCost``. Every
    ``_add_cost`` carries the model id it spent on; a service with no
    model id (a flat-rate provider) passes a synthetic key.
    """

    def _add_cost(self, amount: float, model: str) -> None:
        """Add one paid call's cost to the running total and to ``model``'s
        own bucket."""
        self._cost = getattr(self, "_cost", 0.0) + amount
        by_model = getattr(self, "_by_model", {})
        by_model[model] = by_model.get(model, 0.0) + amount
        self._by_model = by_model

    @property
    def cost(self) -> float:
        """USD this service has spent so far this run."""
        return getattr(self, "_cost", 0.0)

    @property
    def cost_by_model(self) -> dict[str, float]:
        """USD this service has spent so far this run, keyed by model id."""
        return getattr(self, "_by_model", {})
