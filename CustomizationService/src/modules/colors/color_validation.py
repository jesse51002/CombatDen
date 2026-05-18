"""Deterministic, tool-free colour contract.

Pure Python (stdlib ``math`` only — no dependency, no LLM, no MCP). After
the colour LLM returns a palette, this converts each ``oklch(...)`` to
sRGB, computes WCAG relative luminance + contrast between the
``background``- and ``text``-role colours, and enforces strict
impeccable-aligned sanity bounds so neither can be garish.

A failure raises a single, self-describing ``ValueError``. It is invoked
from a ``model_validator`` on the per-request colour response model, so it
rides the existing ``complete_structured`` retry loop — the raised message
flows verbatim into ``schema_correction.md`` and the model is re-asked.
"""

from __future__ import annotations

import math
import re

from schema import ColorOutput, ColorRole

# --- strict sanity bounds (background & text only) -------------------------
# primary/accent (role=None) are intentionally unconstrained.
CHROMA_MIN_TINT = 0.003  # never pure gray/black — require a faint hued tint
CHROMA_MAX_NEUTRAL = 0.04  # base/text colours stay low-chroma, not "designed"
DARK_MODE_BG_L_MAX = 0.30  # dark mode: background pinned near-black
DARK_MODE_TEXT_L_MIN = 0.85  # dark mode: text pinned near-white
LIGHT_MODE_BG_L_MIN = 0.92  # light mode: background pinned near-white
LIGHT_MODE_TEXT_L_MAX = 0.40  # light mode: text pinned near-black
MIN_CONTRAST_AA = 4.5  # WCAG AA, normal text

# Lenient parse: the OklchColor field validator already guaranteed shape +
# numeric ranges before this ever runs; this only needs to read L/C/H back.
_OKLCH_RE = re.compile(
    r"^oklch\(\s*(\d+(?:\.\d+)?)%\s+(\d+(?:\.\d+)?)\s+(\d+(?:\.\d+)?)"
    r"(?:\s*/\s*\d+(?:\.\d+)?%?)?\s*\)$",
    re.IGNORECASE,
)


def _parse_oklch(s: str) -> tuple[float, float, float]:
    """``oklch(L% C H)`` → (L in 0–1, C, H in degrees). Alpha ignored."""
    m = _OKLCH_RE.match(s)
    if m is None:
        raise ValueError(f"not a parseable oklch string: {s!r}")
    return float(m.group(1)) / 100.0, float(m.group(2)), float(m.group(3))


def _gamma_encode(c: float) -> float:
    """Linear sRGB channel → gamma-encoded sRGB in [0, 1].

    OKLCH covers colours outside the sRGB gamut; clamping to [0, 1] before
    encoding is the standard deterministic handling. It affects only the
    sanity/contrast math — the stored ``oklch`` string is preserved verbatim.
    """
    c = min(1.0, max(0.0, c))
    if c <= 0.0031308:
        return 12.92 * c
    return 1.055 * (c ** (1 / 2.4)) - 0.055


def oklch_to_srgb(
    lightness: float, chroma: float, hue: float
) -> tuple[float, float, float]:
    """OKLCH → gamma-encoded sRGB in [0, 1] (Ottosson inverse matrices)."""
    h = math.radians(hue)
    a = chroma * math.cos(h)
    b = chroma * math.sin(h)

    l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
    m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
    s_ = lightness - 0.0894841775 * a - 1.2914855480 * b

    lin_l = l_**3
    lin_m = m_**3
    lin_s = s_**3

    r = 4.0767416621 * lin_l - 3.3077115913 * lin_m + 0.2309699292 * lin_s
    g = -1.2684380046 * lin_l + 2.6097574011 * lin_m - 0.3413193965 * lin_s
    b_ = -0.0041960863 * lin_l - 0.7034186147 * lin_m + 1.7076147010 * lin_s

    return _gamma_encode(r), _gamma_encode(g), _gamma_encode(b_)


def _wcag_linearize(v: float) -> float:
    """WCAG's own linearization of a gamma-encoded sRGB channel.

    Distinct from the linear sRGB inside ``oklch_to_srgb`` — WCAG defines
    its own transfer on the *gamma-encoded* value.
    """
    return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4


def relative_luminance(rgb: tuple[float, float, float]) -> float:
    """WCAG relative luminance from gamma-encoded sRGB in [0, 1]."""
    r, g, b = (_wcag_linearize(c) for c in rgb)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(
    rgb1: tuple[float, float, float], rgb2: tuple[float, float, float]
) -> float:
    """WCAG contrast ratio (1.0 – 21.0); order-independent."""
    lum1 = relative_luminance(rgb1)
    lum2 = relative_luminance(rgb2)
    hi, lo = max(lum1, lum2), min(lum1, lum2)
    return (hi + 0.05) / (lo + 0.05)


def enforce_color_contract(
    resolved: dict[str, ColorOutput],
    *,
    roles: dict[str, ColorRole | None],
    dark_mode: bool,
) -> None:
    """Raise a single actionable ``ValueError`` if the palette violates the
    deterministic contract; return ``None`` if it is clean."""
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

    bg_l, bg_c, bg_h = _parse_oklch(str(resolved[bg_id].oklch))
    tx_l, tx_c, tx_h = _parse_oklch(str(resolved[text_id].oklch))

    # Chroma: low but never pure gray/black (impeccable: faint hued tint).
    for sid, chroma in ((bg_id, bg_c), (text_id, tx_c)):
        if not CHROMA_MIN_TINT <= chroma <= CHROMA_MAX_NEUTRAL:
            raise ValueError(
                f"colour contract: the '{sid}' colour "
                f"({resolved[sid].oklch}) has chroma {chroma:.4f}; "
                f"background/text colours must have chroma in "
                f"[{CHROMA_MIN_TINT}, {CHROMA_MAX_NEUTRAL}] — low-chroma but "
                f"not pure gray/black. Re-pick a near-neutral colour with a "
                f"faint brand-hued tint."
            )

    # Lightness bands by mode.
    if dark_mode:
        if bg_l > DARK_MODE_BG_L_MAX:
            raise ValueError(
                f"colour contract: dark mode — the '{bg_id}' background "
                f"({resolved[bg_id].oklch}) must have lightness ≤ "
                f"{DARK_MODE_BG_L_MAX} (got {bg_l:.2f}). Make it near-black."
            )
        if tx_l < DARK_MODE_TEXT_L_MIN:
            raise ValueError(
                f"colour contract: dark mode — the '{text_id}' text "
                f"({resolved[text_id].oklch}) must have lightness ≥ "
                f"{DARK_MODE_TEXT_L_MIN} (got {tx_l:.2f}). Make it near-white."
            )
    else:
        if bg_l < LIGHT_MODE_BG_L_MIN:
            raise ValueError(
                f"colour contract: light mode — the '{bg_id}' background "
                f"({resolved[bg_id].oklch}) must have lightness ≥ "
                f"{LIGHT_MODE_BG_L_MIN} (got {bg_l:.2f}). Make it near-white."
            )
        if tx_l > LIGHT_MODE_TEXT_L_MAX:
            raise ValueError(
                f"colour contract: light mode — the '{text_id}' text "
                f"({resolved[text_id].oklch}) must have lightness ≤ "
                f"{LIGHT_MODE_TEXT_L_MAX} (got {tx_l:.2f}). Make it near-black."
            )

    # WCAG AA contrast between background and text.
    ratio = contrast_ratio(
        oklch_to_srgb(bg_l, bg_c, bg_h),
        oklch_to_srgb(tx_l, tx_c, tx_h),
    )
    if ratio < MIN_CONTRAST_AA:
        raise ValueError(
            f"colour contract: contrast between the '{text_id}' text "
            f"({resolved[text_id].oklch}) and '{bg_id}' background "
            f"({resolved[bg_id].oklch}) is {ratio:.2f}:1; WCAG AA requires "
            f"≥ {MIN_CONTRAST_AA}:1 for normal text. Widen the lightness "
            f"gap between them."
        )
