"""BriefRequest / BriefCommitted — the brief form's flat wire shape.

One tight unit: what the form posts and what committing it returns.

The brief contract itself is ``schema/customization.py`` and stays the only
authority: **five** fields, ``extra="forbid"``, with the non-empty
validators on all of them. This model is a flat presentation of exactly
those five (mirroring the flag names ``scripts/edit_customization`` already
uses) plus an optional filename ``slug``; it invents nothing. ``build()``
is the single conversion, so validation always runs through
``Customization`` — never a second copy of its rules.

``from_brief()`` is that conversion in reverse, and lives here beside it so
the flat ⇄ nested mapping has exactly one home. The conversational agent
(``src/studio/agent/``) proposes a real ``Customization``; its accept path
flattens it through ``from_brief`` and commits it via the same
``BriefService.commit`` the form posts to. The agent is another caller of
the commit path, never a second commit path.
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

    @classmethod
    def from_brief(
        cls, brief: Customization, slug: PathSegment | None = None
    ) -> BriefRequest:
        """``build()`` in reverse: a nested brief flattened for committing.

        The agent proposes the real ``Customization``, not this flat shape,
        so its accept path needs the mapping the other way round. It lives
        here rather than in the agent so both directions stay in one file and
        can never disagree about which flat name feeds which nested field.
        """
        return cls(
            name=brief.design_direction.name,
            short_desc=brief.design_direction.short_desc,
            long_desc=brief.design_direction.long_desc,
            colors_description=brief.colors_direction.description,
            mode=brief.colors_direction.mode,
            slug=slug,
        )


class BriefCommitted(BaseModel):
    """Where the brief landed, and the validated brief itself."""

    model_config = ConfigDict(extra="forbid")

    slug: str
    path: str
    brief: Customization
