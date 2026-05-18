"""Typed `str` primitives that validate on construction."""

from __future__ import annotations

import re

from pydantic import RootModel, field_validator

# oklch(L% C H) or oklch(L% C H / A). Structural match here; numeric range
# bounds are checked in the validator body for clearer error messages
# (mirrors the regex-then-explain pattern used for the other primitives).
_OKLCH_PATTERN = re.compile(
    r"^oklch\(\s*"
    r"(?P<l>\d+(?:\.\d+)?)%\s+"
    r"(?P<c>\d+(?:\.\d+)?)\s+"
    r"(?P<h>\d+(?:\.\d+)?)"
    r"(?:\s*/\s*(?P<a>\d+(?:\.\d+)?%?))?"
    r"\s*\)$",
    re.IGNORECASE,
)


class OklchColor(RootModel[str]):
    """A CSS ``oklch(L% C H)`` / ``oklch(L% C H / A)`` colour.

    L is a percentage (0–100), C an unbounded-ish chroma (0–0.5 accepted
    syntactically; the strict low-chroma ceiling for base/text colours is
    enforced separately by the deterministic contract, not here, so an
    accent may legitimately push chroma higher), H a hue angle (0–360),
    optional alpha (0–1 or 0%–100%). Serializes as the raw string.
    """

    @field_validator("root")
    @classmethod
    def _is_oklch(cls, v: str) -> str:
        m = _OKLCH_PATTERN.match(v)
        if not m:
            raise ValueError(
                "OklchColor must be 'oklch(L% C H)' or "
                f"'oklch(L% C H / A)'; got {v!r}"
            )
        lightness = float(m.group("l"))
        chroma = float(m.group("c"))
        hue = float(m.group("h"))
        if not 0.0 <= lightness <= 100.0:
            raise ValueError(
                f"OklchColor lightness must be 0–100%; got {lightness}% in {v!r}"
            )
        if not 0.0 <= chroma <= 0.5:
            raise ValueError(
                f"OklchColor chroma must be 0–0.5; got {chroma} in {v!r}"
            )
        if not 0.0 <= hue <= 360.0:
            raise ValueError(
                f"OklchColor hue must be 0–360; got {hue} in {v!r}"
            )
        alpha = m.group("a")
        if alpha is not None:
            a_val = float(alpha[:-1]) / 100.0 if alpha.endswith("%") else float(alpha)
            if not 0.0 <= a_val <= 1.0:
                raise ValueError(
                    f"OklchColor alpha must be 0–1 (or 0%–100%); got {alpha!r}"
                )
        return v

    def __str__(self) -> str:
        return self.root


class AbsolutePath(RootModel[str]):
    """An absolute filesystem path. Serializes as the raw path string."""

    @field_validator("root")
    @classmethod
    def _is_absolute(cls, v: str) -> str:
        if not v.startswith("/"):
            raise ValueError(
                f"AbsolutePath must start with '/'; got {v!r}"
            )
        return v

    def __str__(self) -> str:
        return self.root
