"""IconAttribution — the credit a run owes for the icon set it used.

Present on ``IconSet.attribution`` only when the chosen curated set's
licence requires a visible credit (e.g. CC BY 4.0) *and* at least one icon
was actually copied from it. The consuming MobileApp must surface
``notice`` on an "Open Source Licenses / Acknowledgements" screen.

Absent (``None``) for permissive sets — MIT / ISC / Apache-2.0 / free-with-
no-attribution — which need no in-app credit; their licence-text retention,
where required, is a source-tree concern satisfied by the repo, not the
produced ``output.yaml``.

``extra="ignore"`` like the rest of the output models: a previously-produced
``output.yaml`` carrying a since-removed key must still validate.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, field_validator


class IconAttribution(BaseModel):
    """The visible credit the produced run owes for its icons."""

    model_config = ConfigDict(extra="ignore")

    icon_set: str  # chosen set's id
    name: str  # chosen set's human display name
    license: str  # licence requiring the credit, e.g. "CC-BY-4.0"
    notice: str  # exact attribution text the app must display

    @field_validator("icon_set", "name", "license", "notice")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("IconAttribution field must be non-empty")
        return v
