"""Wire shape for the image group: every produced image slot, with the
metadata the flat ``OutputResponse.images`` map has no room for.

The flat map is a PROJECTION of this group — ``slot -> url``, nothing else —
and it keeps that shape permanently, because two deployed clients
(``ThemeFlutter``'s ``_parseStringMap`` and ``ThemeReact``'s
``parseStringMap``) drop any entry whose value is not a bare string. This
group is where a per-image value that cannot fit in a string goes.

``ImageResponse`` is ``schema.ImageOutput`` PROJECTED, not passed through
like ``color_set`` / ``font_set`` / ``text_set``: the artifact's ``path`` is
an absolute path on the machine that produced the run and its ``prompt`` is
the generation instruction, so neither belongs on a public read API. What
survives is the fetch ``url`` (minted per slot, cache-busted by the stored
``version``) and the ``complexity`` tier the run assigned the prompt.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import Complexity


class ImageResponse(BaseModel):
    """One delivered image: where to fetch it, and the tier that made it."""

    model_config = ConfigDict(extra="forbid")

    url: str
    # ``None`` for a run produced before the complexity classifier existed —
    # the same optionality ``ImageOutput.complexity`` carries on disk. A
    # client must render its absence, never assume a tier.
    complexity: Complexity | None = None


class ImageSetResponse(BaseModel):
    """Every resolved image slot, keyed by slot id."""

    model_config = ConfigDict(extra="forbid")

    images: dict[str, ImageResponse]
