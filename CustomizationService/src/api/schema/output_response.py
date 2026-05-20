"""Wire shapes the API returns: prompts + image URLs, never server paths."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import ColorPalette, Output


class ImageResponse(BaseModel):
    """One image slot as the client sees it: the prompt and a fetch URL."""

    model_config = ConfigDict(extra="forbid")

    prompt: str
    url: str


class ImageSetResponse(BaseModel):
    """The image group, mirroring ``ImageSet`` on the wire: every slot's
    prompt + fetch URL, keyed by slot id."""

    model_config = ConfigDict(extra="forbid")

    images: dict[str, ImageResponse]


class FontResponse(BaseModel):
    """One font slot as the client sees it: the resolved family + a
    fetch URL that resolves the per-variant ``.woff2`` URLs on demand."""

    model_config = ConfigDict(extra="forbid")

    family: str
    category: str
    display_name: str
    description: str
    url: str


class FontSetResponse(BaseModel):
    """The font group, mirroring ``FontSet`` on the wire: every slot's
    family + prose + the per-slot delivery URL, keyed by slot id."""

    model_config = ConfigDict(extra="forbid")

    fonts: dict[str, FontResponse]


class OutputResponse(BaseModel):
    """A run's `output.yaml` with each image's filesystem path replaced
    by a streamable URL and each font slot enriched with a delivery URL.
    The colour group (including its ``mode``) passes through unchanged."""

    model_config = ConfigDict(extra="forbid")

    app: str
    display_name: str
    image_set: ImageSetResponse
    color_set: ColorPalette
    font_set: FontSetResponse

    @classmethod
    def from_output(
        cls, output: Output, app_id: str, run_id: str
    ) -> OutputResponse:
        """Project an `Output` onto the wire shape, minting a per-slot
        fetch URL for each image and each font."""
        return cls(
            app=output.app,
            display_name=output.display_name,
            color_set=output.color_set,
            image_set=ImageSetResponse(
                images={
                    slot_id: ImageResponse(
                        prompt=img.prompt,
                        url=f"/apps/{app_id}/{run_id}/images/{slot_id}",
                    )
                    for slot_id, img in output.image_set.images.items()
                }
            ),
            font_set=FontSetResponse(
                fonts={
                    slot_id: FontResponse(
                        family=font.family,
                        category=font.category,
                        display_name=font.display_name,
                        description=font.description,
                        url=f"/apps/{app_id}/{run_id}/fonts/{slot_id}",
                    )
                    for slot_id, font in output.font_set.fonts.items()
                }
            ),
        )
