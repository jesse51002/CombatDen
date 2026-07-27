"""Typed models for the classification call: the node's output carrier and
the per-request closed wire schema.

Two things live here:

- ``CategoryOutput`` — what ``CategoryNode.run()`` returns and what the seed
  reconstructs a done classification from.
- The per-request closed model built by ``build_category_selection_model``
  for the structured-output call itself.

**Why the vocabulary is enforced by an after-validator, not a static enum.**
The class values are the *app's own* (``app.yaml`` → ``categories``), so no
enum can exist in Python without breaking the app-agnostic rule. The schema is
therefore built per request from the app's list, and membership is enforced by
an after-validator — exactly the pattern the icon module already uses for its
dynamic set-id / icon-name vocabularies (``build_icon_set_selection_model``,
``build_icon_match_model``). A miss raises ``ValueError`` → Pydantic
``ValidationError`` → the existing ``complete_structured`` retry loop re-asks
with the error text (which names the permitted values) folded in. Zero new
retry code, and no dependence on a provider's strict-mode ``enum`` support.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model, model_validator

CATEGORY_SELECTION_MODEL_NAME = "CategorySelection"


class CategoryOutput(BaseModel):
    """The classification node's resolved output.

    ``value`` is the chosen category — one of the app's declared
    ``categories``. It is what lands in ``output.yaml`` as the top-level
    scalar ``Output.category``; ``reason`` is the model's short justification,
    kept for logs and for the caller's benefit but **not** serialized (the
    artifact's wire shape for a classification is a bare string, and every
    consumer — the styles API, both client runtimes, the FastApi backend —
    reads it that way).

    That scalar wire shape is why this model is a module-local carrier rather
    than a group under ``schema/output/``: the run gains no new output *group*,
    only a value for a field that already exists. The seed round-trip still
    holds — ``CategoryOutput(value=<saved category>)`` reconstructs this node
    as done from a saved ``output.yaml`` with nothing lost that the artifact
    ever held.
    """

    model_config = ConfigDict(extra="forbid")

    value: str
    reason: str = ""


def build_category_selection_model(
    categories: frozenset[str],
) -> type[BaseModel]:
    """Closed per-request schema for the classification call.

    One ``category`` field (the chosen value) plus a ``reason``, with an
    after-validator constraining ``category`` to the app-declared vocabulary.
    A pick outside it raises ``ValueError`` → ``ValidationError`` and re-rides
    the structured-output retry loop.

    The produced model keeps the stable name ``CategorySelection`` so error
    messages, logs, and test-fake dispatch stay meaningful.
    """

    def _check_category(self: BaseModel) -> BaseModel:
        if self.category not in categories:
            raise ValueError(
                "category must be one of the app's declared categories "
                f"{sorted(categories)}; got {self.category!r}. Pick the single "
                "best-fit value verbatim from that list — do not invent one, "
                "rephrase one, or change its capitalization."
            )
        return self

    return create_model(
        CATEGORY_SELECTION_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_declared_vocabulary": model_validator(mode="after")(
                _check_category
            )
        },
        category=(str, ...),
        reason=(str, ...),
    )
