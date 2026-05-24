"""Typed models for the two lottie LLM calls: the per-request closed wire
schemas for selection and recolour.

Two closed models are built per call (the same approach as
``font_models.build_font_response_model``): Anthropic strict structured
output rejects open maps and free-form ids, so each schema is constructed
per request with its membership contract as a
``model_validator(mode="after")``. A bad pick raises ``ValueError`` →
Pydantic ``ValidationError`` → the existing ``complete_structured`` retry
loop re-asks. Zero lottie-specific retry code.

- ``build_selection_model`` constrains ``preset_id`` to the candidate
  set offered for this slot.
- ``build_recolor_model`` constrains ``region_roles`` to exactly the
  chosen preset's regions (all present, once) with every value a real
  palette key.

Each factory stamps the contract data it enforced (``candidate_ids`` /
``regions``) onto the returned class so a test fake can construct a valid
response without re-deriving it.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model, model_validator

SELECTION_RESPONSE_MODEL_NAME = "LottieSelection"
RECOLOR_RESPONSE_MODEL_NAME = "LottieRecolor"


def build_selection_model(*, candidate_ids: list[str]) -> type[BaseModel]:
    """Closed wire schema for CALL 1: a single ``preset_id`` the LLM must
    choose from ``candidate_ids`` (the presets carrying the slot's
    required type tag)."""
    allowed = set(candidate_ids)

    def _check_candidate(self: BaseModel) -> BaseModel:
        if self.preset_id not in allowed:  # type: ignore[attr-defined]
            raise ValueError(
                f"preset_id must be one of the offered candidates "
                f"{sorted(allowed)}; got {self.preset_id!r}."  # type: ignore[attr-defined]
            )
        return self

    model = create_model(
        SELECTION_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_candidate_membership": model_validator(mode="after")(
                _check_candidate
            )
        },
        preset_id=(str, ...),
    )
    # Stamp the contract so callers/tests can build a valid response.
    model.candidate_ids = list(candidate_ids)  # type: ignore[attr-defined]
    return model


def build_recolor_model(
    *, regions: list[str], palette_keys: frozenset[str]
) -> type[BaseModel]:
    """Closed wire schema for CALL 2: a ``region_roles`` map the LLM fills
    in. The after-validator enforces that the keys are exactly the chosen
    preset's regions (every one, no extras) and that every value is a real
    palette key (a key in ``ColorPalette.palette`` — base role or derived
    key)."""
    required_regions = set(regions)

    def _check_mapping(self: BaseModel) -> BaseModel:
        got = set(self.region_roles)  # type: ignore[attr-defined]
        missing = sorted(required_regions - got)
        extra = sorted(got - required_regions)
        if missing or extra:
            raise ValueError(
                "region_roles must map exactly the preset's regions "
                f"{sorted(required_regions)}. "
                f"Missing: {missing}. Unexpected: {extra}."
            )
        bad = sorted(
            {
                f"{region}={role!r}"
                for region, role in self.region_roles.items()  # type: ignore[attr-defined]
                if role not in palette_keys
            }
        )
        if bad:
            raise ValueError(
                "every region must map to a real palette key (one of the "
                "listed keys, base or derived). Not a palette key: "
                f"{bad}."
            )
        return self

    model = create_model(
        RECOLOR_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_enforce_region_role_contract": model_validator(mode="after")(
                _check_mapping
            )
        },
        region_roles=(dict[str, str], ...),
    )
    model.regions = list(regions)  # type: ignore[attr-defined]
    return model
