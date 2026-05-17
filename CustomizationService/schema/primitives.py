"""Typed `str` primitives that validate on construction."""

from __future__ import annotations

import re

from pydantic import RootModel, field_validator

_HEX_PATTERN = re.compile(r"^#[0-9A-Fa-f]{6}$")


class HexColor(RootModel[str]):
    """A `#RRGGBB` hex color. Serializes as the raw hex string."""

    @field_validator("root")
    @classmethod
    def _is_hex(cls, v: str) -> str:
        if not _HEX_PATTERN.match(v):
            raise ValueError(
                f"HexColor must be #RRGGBB (6 hex digits); got {v!r}"
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
