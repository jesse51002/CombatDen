"""Wire shape the API returns: flat slot-keyed maps, never server paths.

`images` and `fonts` each collapse to a `dict[str, str]` — slot id maps
directly to the value a client actually needs (a fetch URL for an
image, a Google Fonts family name for a font). The colour and text
groups pass through unchanged: they already carry exactly what the
client consumes.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import ColorPalette, Output, TextSet


class OutputResponse(BaseModel):
    """A run's `output.yaml` projected onto the wire. Images become
    `slot -> URL`; fonts become `slot -> Google Fonts family`. The
    colour and text groups are byte-identical with disk."""

    model_config = ConfigDict(extra="forbid")

    app: str
    display_name: str
    images: dict[str, str]
    fonts: dict[str, str]
    color_set: ColorPalette
    text_set: TextSet

    @classmethod
    def from_output(
        cls, output: Output, app_id: str, run_id: str
    ) -> OutputResponse:
        """Project an `Output` onto the wire shape, minting a per-slot
        fetch URL for each image and collapsing each font slot to its
        Google Fonts family."""
        return cls(
            app=output.app,
            display_name=output.display_name,
            color_set=output.color_set,
            text_set=output.text_set,
            images={
                slot_id: f"/apps/{app_id}/{run_id}/images/{slot_id}"
                for slot_id in output.image_set.images
            },
            fonts={
                slot_id: font.family
                for slot_id, font in output.font_set.fonts.items()
            },
        )
