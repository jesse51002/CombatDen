"""ColorMode — whether a resolved palette targets a light or dark UI.

Set on the input (`ColorsDirection`) and carried through to the output
(`ColorPalette`) so a consumer of `output.yaml` can tell which mode a
palette was generated for. Serializes as ``"light"`` / ``"dark"``.
"""

from __future__ import annotations

import enum


class ColorMode(str, enum.Enum):
    """The two palette modes."""

    LIGHT = "light"
    DARK = "dark"
