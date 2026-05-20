"""ColorCorrectionService + colour contract: the OKLCH primitive, the
contract (now inlined as the LLM response model's ``model_validator``),
the bg-lightness clamp, and the LLM retry-loop reuse.

After the contract moved from a wrapper function into the
``model_validator``, the contract tests construct the per-request
response model directly and expect ``ValidationError`` on bad input —
that's the actual path the LLM call takes. The bg-clamp tests stay
unchanged; that helper still lives on ``ColorCorrectionService``."""

from __future__ import annotations

import asyncio
import json

import litellm
import pytest
from pydantic import ValidationError

from schema import AppFormat, ColorRole, OklchColor
from src.core.errors import SchemaValidationError
from src.modules.colors.color_correction_service import ColorCorrectionService
from src.modules.colors.color_models import (
    MIN_CONTRAST_AA,
    LLMSlotResponse,
    _contrast_ratio,
    build_color_response_model,
)
from src.shared.services.llm_client import LiteLLMClient

# Aliases for readability — every helper lives on the service class now.
_clamp = ColorCorrectionService._clamp_bg_lightness
_contrast = _contrast_ratio

# litellm.acompletion is monkeypatched, but _completion_kwargs still resolves
# the provider key from this prefix, so it must be a configured provider.
_MODEL = "anthropic/claude-haiku-4-5-20251001"


# --- OklchColor primitive --------------------------------------------------


@pytest.mark.parametrize(
    "kwargs",
    [
        {"l": 0.60, "c": 0.12, "h": 250.0},
        {"l": 0.50, "c": 0.10, "h": 120.0, "alpha": 0.5},
        {"l": 0.0, "c": 0.0, "h": 0.0},  # pure black
        {"l": 1.0, "c": 0.0, "h": 0.0},  # pure white
    ],
)
def test_oklch_color_accepts_valid(kwargs):
    o = OklchColor(**kwargs)
    # Round-trips through coloraide and back.
    again = OklchColor.from_aide(o.to_aide())
    assert abs(again.l - o.l) < 1e-6
    assert abs(again.c - o.c) < 1e-6
    # Hue can flip from 0 to 360 on the wire for a zero-chroma colour;
    # both are equivalent.
    assert abs((again.h - o.h) % 360.0) < 1e-3


@pytest.mark.parametrize(
    "kwargs",
    [
        {"l": -0.1, "c": 0.1, "h": 10.0},  # L below 0
        {"l": 1.5, "c": 0.1, "h": 10.0},  # L above 1
        {"l": 0.5, "c": 0.9, "h": 10.0},  # C above 0.5
        {"l": 0.5, "c": 0.1, "h": 400.0},  # H above 360
        {"l": 0.5, "c": 0.1, "h": 10.0, "alpha": 1.5},  # alpha out of range
    ],
)
def test_oklch_color_rejects_invalid(kwargs):
    with pytest.raises(ValidationError):
        OklchColor(**kwargs)


def test_oklch_color_from_css_round_trips():
    o = OklchColor.from_css("oklch(70% 0.19 41)")
    assert abs(o.l - 0.70) < 1e-6
    assert abs(o.c - 0.19) < 1e-6
    assert abs(o.h - 41.0) < 1e-3
    # And produces the canonical CSS string via __str__.
    assert str(o) == "oklch(70% 0.19 41)"


def test_oklch_color_str_form_matches_css():
    # No alpha → no "/" segment.
    assert str(OklchColor(l=0.5, c=0.1, h=200.0)) == "oklch(50% 0.1 200)"
    # Alpha present → "/A".
    assert (
        str(OklchColor(l=0.5, c=0.1, h=200.0, alpha=0.25))
        == "oklch(50% 0.1 200 / 0.25)"
    )


# --- WCAG contrast (via coloraide) ----------------------------------------
# Per-channel sRGB / luminance helpers are no longer ours — coloraide owns
# the math. The behavioural contract we depend on is just: white/black ≈ 21,
# same colour against itself = 1, and order-independence.


def test_contrast_known_pairs() -> None:
    white = OklchColor(l=1.0, c=0.0, h=0.0)
    black = OklchColor(l=0.0, c=0.0, h=0.0)
    assert abs(_contrast(white, black) - 21.0) < 0.05
    assert abs(_contrast(white, white) - 1.0) < 1e-6
    # Order-independent.
    assert (
        abs(_contrast(white, black)
            - _contrast(black, white))
        < 1e-9
    )


# --- the contract (now inlined as a model_validator) ---------------------

_ROLES = {
    "primary": None,
    "background": ColorRole.BACKGROUND,
    "text": ColorRole.TEXT,
}


def _slot(oklch_css: str, name: str = "n") -> LLMSlotResponse:
    return LLMSlotResponse(
        oklch=OklchColor.from_css(oklch_css),
        display_name=name,
        description=f"the {name} slot",
    )


def _try_palette(
    *,
    bg: str,
    text: str,
    primary: str = "oklch(55% 0.18 25)",
    roles: dict[str, ColorRole | None] = _ROLES,
    dark_mode: bool,
):
    """Build the per-request response model and try to construct it.

    The contract is now the model_validator on this dynamic model, so
    "did the contract pass?" is just "did construction succeed?".
    Returns the constructed instance on pass; raises ``ValidationError``
    on fail (with the contract's ``ValueError`` message inside)."""
    model = build_color_response_model(
        list(roles.keys()), roles=roles, dark_mode=dark_mode
    )
    return model(
        primary=_slot(primary, "primary"),
        background=_slot(bg, "background"),
        text=_slot(text, "text"),
    )


def test_contract_passes_dark_mode() -> None:
    _try_palette(
        bg="oklch(15% 0.012 40)", text="oklch(92% 0.01 80)", dark_mode=True
    )


def test_contract_passes_light_mode() -> None:
    _try_palette(
        bg="oklch(96% 0.006 250)", text="oklch(20% 0.01 250)", dark_mode=False
    )


@pytest.mark.parametrize(
    ("bg", "text", "dark", "needle"),
    [
        ("oklch(15% 0.20 40)", "oklch(92% 0.01 80)", True, "chroma"),
        # Background lightness is no longer a contract raise (the clamp owns
        # it); the contract still rejects a too-narrow text/bg contrast gap.
        ("oklch(45% 0.012 40)", "oklch(40% 0.01 80)", False, "contrast"),
        ("oklch(15% 0.012 40)", "oklch(40% 0.01 80)", True, "lightness"),
        ("oklch(15% 0.0 40)", "oklch(92% 0.01 80)", True, "chroma"),
        ("oklch(95% 0.006 250)", "oklch(60% 0.01 250)", False, "lightness"),
    ],
)
def test_contract_fail_modes(
    bg: str, text: str, dark: bool, needle: str
) -> None:
    with pytest.raises(ValidationError, match=needle):
        _try_palette(bg=bg, text=text, dark_mode=dark)


def test_contract_requires_exactly_one_background_and_text() -> None:
    # The roles-cardinality check now lives at build time (the dynamic
    # model can't be built if there isn't exactly one bg + one text),
    # not at validation time — bg/text are the closure handles every
    # per-slot validator needs.
    with pytest.raises(ValueError, match="background"):
        build_color_response_model(
            ["primary", "background", "text"],
            roles={
                "primary": None,
                "background": None,
                "text": ColorRole.TEXT,
            },
            dark_mode=True,
        )


# --- clamp_bg_lightness ----------------------------------------------------


def test_clamp_light_bg_pulled_below_ceiling() -> None:
    # Only L is rewritten to the 0.90 ceiling; C/H/alpha preserved structurally.
    out = _clamp(
        OklchColor(l=0.97, c=0.0123, h=70.5), dark_mode=False
    )
    assert out.l == 0.90
    assert out.c == 0.0123
    assert out.h == 70.5
    assert out.alpha is None


def test_clamp_dark_bg_lifted_above_floor() -> None:
    out = _clamp(
        OklchColor(l=0.03, c=0.006, h=40.0), dark_mode=True
    )
    assert out.l == 0.08
    assert out.c == 0.006
    assert out.h == 40.0


def test_clamp_in_band_is_identity() -> None:
    src = OklchColor(l=0.88, c=0.01, h=250.0)  # within light band [0.86, 0.90]
    assert _clamp(src, dark_mode=False) is src


def test_clamp_is_idempotent() -> None:
    once = _clamp(
        OklchColor(l=0.99, c=0.02, h=30.0), dark_mode=False
    )
    twice = _clamp(once, dark_mode=False)
    assert once.l == twice.l == 0.90


def test_clamp_preserves_alpha() -> None:
    out = _clamp(
        OklchColor(l=0.05, c=0.006, h=40.0, alpha=0.5), dark_mode=True
    )
    assert out.l == 0.08
    assert out.alpha == 0.5


def test_clamp_preserves_aa_contrast_at_boundaries() -> None:
    """The contract validates contrast on the *pre-clamp* background;
    assert the post-clamp background still clears WCAG AA against
    worst-case boundary text in both modes."""
    light_bg = _clamp(
        OklchColor(l=0.99, c=0.006, h=250.0), dark_mode=False
    )
    light_text = OklchColor(l=0.40, c=0.01, h=250.0)  # darkest light-mode text
    assert _contrast(light_bg, light_text) >= MIN_CONTRAST_AA

    dark_bg = _clamp(
        OklchColor(l=0.02, c=0.006, h=40.0), dark_mode=True
    )
    dark_text = OklchColor(l=0.85, c=0.01, h=80.0)  # darkest dark-mode text
    assert _contrast(dark_bg, dark_text) >= MIN_CONTRAST_AA


# --- AppFormat role gate ---------------------------------------------------


def _app(colors: list[dict]) -> dict:
    return {
        "id": "x",
        "display_name": "X",
        "images": [{"id": "img", "description": "an image"}],
        "colors": colors,
        "fonts": [{"id": "body", "description": "running UI text"}],
    }


def test_app_format_accepts_exactly_one_bg_and_text() -> None:
    AppFormat.model_validate(
        _app(
            [
                {"id": "primary", "description": "p"},
                {"id": "background", "description": "b", "role": "background"},
                {"id": "text", "description": "t", "role": "text"},
            ]
        )
    )


@pytest.mark.parametrize(
    "colors",
    [
        # two backgrounds (count > 1)
        [
            {"id": "background", "description": "b", "role": "background"},
            {"id": "bg2", "description": "b2", "role": "background"},
            {"id": "text", "description": "t", "role": "text"},
        ],
        # zero text (count = 0, the other role)
        [{"id": "background", "description": "b", "role": "background"}],
    ],
)
def test_app_format_rejects_bad_role_counts(colors: list[dict]) -> None:
    with pytest.raises(ValidationError):
        AppFormat.model_validate(_app(colors))


# --- integration: contract failure rides the existing retry loop -----------


class _FakeMessage:
    def __init__(self, content: str) -> None:
        self.content = content

    def model_dump(self) -> dict:
        return {"role": "assistant", "content": self.content}

    def __getitem__(self, key: str):
        if key == "content":
            return self.content
        raise KeyError(key)


class _FakeChoice:
    def __init__(self, content: str) -> None:
        self.message = _FakeMessage(content)


class _FakeCompletion:
    def __init__(self, content: str) -> None:
        self.choices = [_FakeChoice(content)]


def test_contract_failure_reasks_then_succeeds(monkeypatch) -> None:
    """OklchColor is now a structured model on the wire — the LLM JSON
    nests ``oklch: {l, c, h}`` instead of emitting a CSS string."""
    model = build_color_response_model(
        ["background", "text"],
        roles={"background": ColorRole.BACKGROUND, "text": ColorRole.TEXT},
        dark_mode=True,
    )
    bad = json.dumps(
        {
            "background": {
                "oklch": {"l": 0.70, "c": 0.02, "h": 40.0},  # too light for dark
                "display_name": "Too Light",
                "description": "bad bg",
            },
            "text": {
                "oklch": {"l": 0.92, "c": 0.01, "h": 80.0},
                "display_name": "Bone",
                "description": "text",
            },
        }
    )
    good = json.dumps(
        {
            "background": {
                "oklch": {"l": 0.15, "c": 0.012, "h": 40.0},
                "display_name": "Canvas Black",
                "description": "bg",
            },
            "text": {
                "oklch": {"l": 0.92, "c": 0.01, "h": 80.0},
                "display_name": "Bone",
                "description": "text",
            },
        }
    )
    seq = [bad, good]
    calls = {"n": 0}

    async def fake_acompletion(**kwargs):
        i = calls["n"]
        calls["n"] += 1
        return _FakeCompletion(seq[min(i, len(seq) - 1)])

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)

    result = asyncio.run(
        LiteLLMClient().complete_structured(
            [{"role": "user", "content": "palette"}],
            schema=model,
            model=_MODEL,
        )
    )

    # First answer rejected by the contract, second one accepted: the
    # existing complete_structured loop re-asked exactly once.
    assert calls["n"] == 2
    assert result.background.oklch.l == 0.15


def test_contract_failure_exhausts_to_schema_error(monkeypatch) -> None:
    model = build_color_response_model(
        ["background", "text"],
        roles={"background": ColorRole.BACKGROUND, "text": ColorRole.TEXT},
        dark_mode=True,
    )
    always_bad = json.dumps(
        {
            "background": {
                "oklch": {"l": 0.70, "c": 0.02, "h": 40.0},
                "display_name": "Too Light",
                "description": "bad bg",
            },
            "text": {
                "oklch": {"l": 0.92, "c": 0.01, "h": 80.0},
                "display_name": "Bone",
                "description": "text",
            },
        }
    )

    async def fake_acompletion(**kwargs):
        return _FakeCompletion(always_bad)

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)

    with pytest.raises(SchemaValidationError):
        asyncio.run(
            LiteLLMClient().complete_structured(
                [{"role": "user", "content": "palette"}],
                schema=model,
                model=_MODEL,
            )
        )
