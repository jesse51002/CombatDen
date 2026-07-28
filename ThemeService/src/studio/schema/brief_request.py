"""BriefRequest / BriefCommitted — the brief form's flat wire shape.

One tight unit: what the form posts and what committing it returns.

The brief contract itself is ``schema/customization.py`` and stays the only
authority: **five** fields, ``extra="forbid"``, with the non-empty
validators on all of them. This model is a flat presentation of exactly
those five (mirroring the flag names ``scripts/edit_customization`` already
uses) plus an optional filename ``slug``; it invents nothing. ``build()``
is the single conversion, so validation always runs through
``Customization`` — never a second copy of its rules.

The conversational (Pydantic AI) authoring agent is a follow-up. When it
lands, its accept path calls the same ``BriefService.commit`` over this
same model — the agent will be another caller of the commit path, not a
second commit path.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import ColorMode, Customization, PathSegment


class BriefRequest(BaseModel):
    """The five brief fields, flat, plus an optional filename slug."""

    model_config = ConfigDict(extra="forbid")

    name: str
    short_desc: str
    long_desc: str
    colors_description: str
    mode: ColorMode
    # Defaults to a slug derived from ``name`` (see BriefService).
    slug: PathSegment | None = None

    def build(self) -> Customization:
        """This request as the real brief contract.

        Raises ``pydantic.ValidationError`` when a field is blank — the
        validators live on ``Customization``, which is the point.
        """
        return Customization.model_validate(
            {
                "design_direction": {
                    "name": self.name,
                    "short_desc": self.short_desc,
                    "long_desc": self.long_desc,
                },
                "colors_direction": {
                    "description": self.colors_description,
                    "mode": self.mode,
                },
            }
        )


class BriefCommitted(BaseModel):
    """Where the brief landed, and the validated brief itself."""

    model_config = ConfigDict(extra="forbid")

    slug: str
    path: str
    brief: Customization
