"""Typed models for the colour LLM call: per-slot wire shape, the
contract-clean palette handoff, and the per-request closed wire schema
builder (with the deterministic contract inlined as its
``model_validator``).

The LLM is asked for ONLY the base colour value (in OKLCH) plus the
prose fields. Every other shape on the eventual ``ColorOutput`` — the
HSL/RGB/hex projections, the six derivations, the flat recommendation
palette — is computed deterministically downstream:
``ColorCorrectionService`` clamps the background L band, then
``ColorDerivationService`` builds everything else.

Three models live here:

- ``LLMSlotResponse`` — the narrow per-slot wire type the LLM fills in.
- ``PaletteSchema`` — the typed handoff between the colour services
  after the LLM call and contract pass.
- The per-request closed model built by ``build_color_response_model``
  for the structured-output call itself, with the contract as its
  after-validator (no separate wrapper function — that *is* what
  ``model_validator(mode="after")`` is for).
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, create_model, model_validator

from schema import ColorMode, ColorRole, OklchColor

COLOR_RESPONSE_MODEL_NAME = "ColorPalette"

# --- strict contract bounds (background & text only) ----------------------
# primary/accent (role=None) are intentionally unconstrained.
CHROMA_MIN_TINT = 0.003  # never pure gray/black — require a faint hued tint
CHROMA_MAX_NEUTRAL = 0.04  # base/text colours stay low-chroma, not "designed"
DARK_MODE_TEXT_L_MIN = 0.85  # dark mode: text pinned near-white
LIGHT_MODE_TEXT_L_MAX = 0.40  # light mode: text pinned near-black
MIN_CONTRAST_AA = 4.5  # WCAG AA, normal text

# Background lightness is intentionally NOT a contract bound — it's the
# one thing ``ColorCorrectionService.apply`` corrects deterministically
# rather than re-asking the LLM. See that service for the band bounds.


def _contrast_ratio(a: OklchColor, b: OklchColor) -> float:
    """WCAG 2.1 contrast ratio between two OKLCH colours, via coloraide.
    Module-level helper used only by the validator below — kept here so
    the contract logic lives in one file."""
    return a.to_aide().contrast(b.to_aide(), method="wcag21")


class LLMSlotResponse(BaseModel):
    """What the LLM returns for one colour slot, before pipeline post-
    processing builds the full ``ColorOutput``.

    Narrow on purpose: structured-output APIs that expose this schema to
    the model should only show the fields the model needs to choose. The
    extra formats (hsl/rgb/hex), the derivations dict, and the flat
    palette are pipeline outputs, not LLM ones.
    """

    model_config = ConfigDict(extra="forbid")

    oklch: OklchColor
    display_name: str  # evocative human label, e.g. "Warm Ash Cream"
    description: str  # purpose/usage prose for the colour


class PaletteSchema(BaseModel):
    """The LLM-resolved palette, before any post-LLM correction or
    derivation. Internal handoff between the three colour services
    (scheme → correction → derivation).

    Lives in ``color_models`` (next to ``LLMSlotResponse``) because it
    IS the typed wire-shaped result of the colour LLM call; the scheme
    service is just what produces it.
    """

    model_config = ConfigDict(extra="forbid")

    mode: ColorMode
    roles: dict[str, ColorRole | None]
    colors: dict[str, LLMSlotResponse]


def build_color_response_model(
    slot_ids: list[str],
    *,
    roles: dict[str, ColorRole | None],
    dark_mode: bool,
) -> type[BaseModel]:
    """Closed per-request wire schema: one required ``LLMSlotResponse``
    per slot, plus the deterministic colour contract inlined as the
    ``model_validator(mode="after")``.

    Anthropic strict structured output rejects open maps — ``dict[str,
    X]`` renders ``additionalProperties`` as a schema, which it forbids.
    So the schema sent for the colour call is built per request with an
    explicit, *required* field for every requested slot id. Slot ids
    come from app YAML and are already snake_case-validated
    (``SlotBase``), so they are valid Python identifiers and safe as
    model field names.

    Completeness is therefore structural: a missing slot is a Pydantic
    ``ValidationError`` the llm client's retry loop re-asks on. The
    same loop also drives the cross-slot contrast/sanity contract: the
    closure-captured ``model_validator(mode="after")`` runs the
    inlined contract logic below (which needs the slot→role map +
    ``dark_mode``, neither of which is in the LLM response). A raised
    ``ValueError`` surfaces as a ``ValidationError`` the existing
    ``complete_structured`` loop catches and feeds back via
    ``schema_correction.md`` — zero new loop code, faithful to "the
    same retry pattern".

    The produced model keeps the stable name ``ColorPalette`` so error
    messages, logs, and test dispatch stay meaningful.
    """
    bg_ids = [sid for sid, r in roles.items() if r is ColorRole.BACKGROUND]
    text_ids = [sid for sid, r in roles.items() if r is ColorRole.TEXT]
    if len(bg_ids) != 1:
        raise ValueError(
            f"colour contract needs exactly one 'background'-role slot; "
            f"got {bg_ids}"
        )
    if len(text_ids) != 1:
        raise ValueError(
            f"colour contract needs exactly one 'text'-role slot; "
            f"got {text_ids}"
        )
    bg_id, text_id = bg_ids[0], text_ids[0]

    def _validate(self: BaseModel) -> BaseModel:
        bg = getattr(self, bg_id).oklch
        text = getattr(self, text_id).oklch

        # Chroma: low but never pure gray/black (impeccable: faint hued tint).
        for sid, color in ((bg_id, bg), (text_id, text)):
            if not CHROMA_MIN_TINT <= color.c <= CHROMA_MAX_NEUTRAL:
                raise ValueError(
                    f"colour contract: the '{sid}' colour "
                    f"(L={color.l:.3f} C={color.c:.4f} H={color.h:.1f}) has "
                    f"chroma {color.c:.4f}; background/text colours must "
                    f"have chroma in "
                    f"[{CHROMA_MIN_TINT}, {CHROMA_MAX_NEUTRAL}] — low-chroma "
                    f"but not pure gray/black. Re-pick a near-neutral colour "
                    f"with a faint brand-hued tint."
                )

        # Text lightness by mode. Background lightness is intentionally
        # NOT checked — the bg clamp in ColorCorrectionService is its
        # sole authority, so a near-extreme background is corrected
        # rather than re-asked or failed.
        if dark_mode:
            if text.l < DARK_MODE_TEXT_L_MIN:
                raise ValueError(
                    f"colour contract: dark mode — the '{text_id}' text "
                    f"(L={text.l:.3f}) must have lightness ≥ "
                    f"{DARK_MODE_TEXT_L_MIN}. Make it near-white."
                )
        else:
            if text.l > LIGHT_MODE_TEXT_L_MAX:
                raise ValueError(
                    f"colour contract: light mode — the '{text_id}' text "
                    f"(L={text.l:.3f}) must have lightness ≤ "
                    f"{LIGHT_MODE_TEXT_L_MAX}. Make it near-black."
                )

        # WCAG AA contrast between background and text — via coloraide.
        ratio = _contrast_ratio(bg, text)
        if ratio < MIN_CONTRAST_AA:
            raise ValueError(
                f"colour contract: contrast between the '{text_id}' text "
                f"(L={text.l:.3f}) and '{bg_id}' background "
                f"(L={bg.l:.3f}) is {ratio:.2f}:1; WCAG AA requires "
                f"≥ {MIN_CONTRAST_AA}:1 for normal text. Widen the "
                f"lightness gap between them."
            )
        return self

    return create_model(
        COLOR_RESPONSE_MODEL_NAME,
        __config__=ConfigDict(extra="forbid"),
        __validators__={
            "_validate_contract": model_validator(mode="after")(_validate)
        },
        **{slot_id: (LLMSlotResponse, ...) for slot_id in slot_ids},
    )
