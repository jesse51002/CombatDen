"""Deterministic colour contract: oklch math, contrast, and the loop reuse."""

from __future__ import annotations

import asyncio
import json

import litellm
import pytest
from pydantic import ValidationError

from schema import AppFormat, ColorOutput, ColorRole, OklchColor
from src.core.errors import SchemaValidationError
from src.modules.colors.color_models import build_color_response_model
from src.modules.colors.color_validation import (
    MIN_CONTRAST_AA,
    _parse_oklch,
    clamp_bg_lightness,
    contrast_ratio,
    enforce_color_contract,
    oklch_to_srgb,
)
from src.shared.services.llm_client import LiteLLMClient

# litellm.acompletion is monkeypatched, but _completion_kwargs still resolves
# the provider key from this prefix, so it must be a configured provider.
_MODEL = "anthropic/claude-haiku-4-5-20251001"


# --- OklchColor primitive --------------------------------------------------


@pytest.mark.parametrize(
    "value",
    [
        "oklch(60% 0.12 250)",  # plain
        "oklch(50% 0.1 120 / 0.5)",  # with alpha
        "oklch( 62%  0.19  28 )",  # tolerant of internal whitespace
    ],
)
def test_oklch_color_accepts_valid(value: str) -> None:
    assert str(OklchColor.model_validate(value)) == value


@pytest.mark.parametrize(
    "value",
    [
        "oklch(60 0.12 250)",  # missing % on L (structural)
        "oklch(120% 0.1 10)",  # L out of range (numeric bound)
        "oklch(60% 0.9 10)",  # chroma out of range (numeric bound)
        "#AA1122",  # wrong format entirely (old hex — regression guard)
    ],
)
def test_oklch_color_rejects_invalid(value: str) -> None:
    with pytest.raises(ValidationError):
        OklchColor.model_validate(value)


# --- oklch -> sRGB -> contrast math ---------------------------------------


def test_oklch_to_srgb_reference_anchors() -> None:
    white = oklch_to_srgb(1.0, 0.0, 0.0)
    black = oklch_to_srgb(0.0, 0.0, 0.0)
    mid = oklch_to_srgb(0.5, 0.0, 0.0)
    assert all(abs(c - 1.0) < 1e-3 for c in white)
    assert all(abs(c - 0.0) < 1e-3 for c in black)
    assert all(abs(c - 0.3886) < 1e-3 for c in mid)


def test_contrast_known_pairs() -> None:
    white = oklch_to_srgb(1.0, 0.0, 0.0)
    black = oklch_to_srgb(0.0, 0.0, 0.0)
    assert abs(contrast_ratio(white, black) - 21.0) < 0.05
    assert abs(contrast_ratio(white, white) - 1.0) < 1e-6
    # Order-independent.
    assert contrast_ratio(white, black) == contrast_ratio(black, white)


# --- enforce_color_contract ------------------------------------------------

_ROLES = {
    "primary": None,
    "background": ColorRole.BACKGROUND,
    "text": ColorRole.TEXT,
}


def _palette(bg: str, text: str, primary: str = "oklch(55% 0.18 25)") -> dict:
    return {
        "primary": ColorOutput(
            oklch=primary, display_name="P", description="primary"
        ),
        "background": ColorOutput(
            oklch=bg, display_name="B", description="background"
        ),
        "text": ColorOutput(oklch=text, display_name="T", description="text"),
    }


def test_contract_passes_dark_mode() -> None:
    enforce_color_contract(
        _palette("oklch(15% 0.012 40)", "oklch(92% 0.01 80)"),
        roles=_ROLES,
        dark_mode=True,
    )


def test_contract_passes_light_mode() -> None:
    enforce_color_contract(
        _palette("oklch(96% 0.006 250)", "oklch(20% 0.01 250)"),
        roles=_ROLES,
        dark_mode=False,
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
    with pytest.raises(ValueError, match=needle):
        enforce_color_contract(
            _palette(bg, text), roles=_ROLES, dark_mode=dark
        )


def test_contract_requires_exactly_one_background_and_text() -> None:
    with pytest.raises(ValueError, match="background"):
        enforce_color_contract(
            _palette("oklch(15% 0.012 40)", "oklch(92% 0.01 80)"),
            roles={"primary": None, "background": None, "text": ColorRole.TEXT},
            dark_mode=True,
        )


# --- clamp_bg_lightness ----------------------------------------------------


def _bg(oklch: str) -> ColorOutput:
    return ColorOutput(
        oklch=oklch, display_name="BG name", description="bg desc"
    )


def test_clamp_light_bg_pulled_below_ceiling() -> None:
    out = clamp_bg_lightness(_bg("oklch(97% 0.0123 70.5)"), dark_mode=False)
    # Only the L token is rewritten to the 0.90 ceiling; chroma/hue tokens
    # stay byte-identical and the prose is untouched.
    assert str(out.oklch) == "oklch(90% 0.0123 70.5)"
    assert out.display_name == "BG name"
    assert out.description == "bg desc"


def test_clamp_dark_bg_lifted_above_floor() -> None:
    out = clamp_bg_lightness(_bg("oklch(3% 0.006 40)"), dark_mode=True)
    assert str(out.oklch) == "oklch(8% 0.006 40)"


def test_clamp_in_band_is_identity() -> None:
    src = _bg("oklch(88% 0.01 250)")  # within the light band [86%, 90%]
    assert clamp_bg_lightness(src, dark_mode=False) is src


def test_clamp_is_idempotent() -> None:
    once = clamp_bg_lightness(_bg("oklch(99% 0.02 30)"), dark_mode=False)
    twice = clamp_bg_lightness(once, dark_mode=False)
    assert str(once.oklch) == str(twice.oklch) == "oklch(90% 0.02 30)"


def test_clamp_preserves_alpha_token() -> None:
    out = clamp_bg_lightness(_bg("oklch(5% 0.006 40 / 0.5)"), dark_mode=True)
    assert str(out.oklch) == "oklch(8% 0.006 40 / 0.5)"


def test_clamp_preserves_aa_contrast_at_boundaries() -> None:
    """The contract validates contrast on the *pre-clamp* background; assert
    the post-clamp background still clears WCAG AA against worst-case
    boundary text in both modes."""
    light_bg = clamp_bg_lightness(_bg("oklch(99% 0.006 250)"), dark_mode=False)
    bl, bc, bh = _parse_oklch(str(light_bg.oklch))
    tl, tc, th = _parse_oklch("oklch(40% 0.01 250)")  # darkest light text
    assert (
        contrast_ratio(oklch_to_srgb(bl, bc, bh), oklch_to_srgb(tl, tc, th))
        >= MIN_CONTRAST_AA
    )
    dark_bg = clamp_bg_lightness(_bg("oklch(2% 0.006 40)"), dark_mode=True)
    bl, bc, bh = _parse_oklch(str(dark_bg.oklch))
    tl, tc, th = _parse_oklch("oklch(85% 0.01 80)")  # darkest dark-mode text
    assert (
        contrast_ratio(oklch_to_srgb(bl, bc, bh), oklch_to_srgb(tl, tc, th))
        >= MIN_CONTRAST_AA
    )


# --- AppFormat role gate ---------------------------------------------------


def _app(colors: list[dict]) -> dict:
    return {
        "id": "x",
        "display_name": "X",
        "images": [{"id": "img", "description": "an image"}],
        "colors": colors,
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
    model = build_color_response_model(
        ["background", "text"],
        roles={"background": ColorRole.BACKGROUND, "text": ColorRole.TEXT},
        dark_mode=True,
    )
    bad = json.dumps(
        {
            "background": {
                "oklch": "oklch(70% 0.02 40)",  # too light for dark mode
                "display_name": "Too Light",
                "description": "bad bg",
            },
            "text": {
                "oklch": "oklch(92% 0.01 80)",
                "display_name": "Bone",
                "description": "text",
            },
        }
    )
    good = json.dumps(
        {
            "background": {
                "oklch": "oklch(15% 0.012 40)",
                "display_name": "Canvas Black",
                "description": "bg",
            },
            "text": {
                "oklch": "oklch(92% 0.01 80)",
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
    assert str(result.background.oklch) == "oklch(15% 0.012 40)"


def test_contract_failure_exhausts_to_schema_error(monkeypatch) -> None:
    model = build_color_response_model(
        ["background", "text"],
        roles={"background": ColorRole.BACKGROUND, "text": ColorRole.TEXT},
        dark_mode=True,
    )
    always_bad = json.dumps(
        {
            "background": {
                "oklch": "oklch(70% 0.02 40)",
                "display_name": "Too Light",
                "description": "bad bg",
            },
            "text": {
                "oklch": "oklch(92% 0.01 80)",
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
