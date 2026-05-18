"""Wire shapes the API returns: prompts + image URLs, never server paths."""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import ColorOutput, Output


class ImageResponse(BaseModel):
    """One image slot as the client sees it: the prompt and a fetch URL."""

    model_config = ConfigDict(extra="forbid")

    prompt: str
    url: str


class OutputResponse(BaseModel):
    """A run's `output.yaml` with each image's filesystem path replaced by
    a streamable URL. Colours pass through unchanged."""

    model_config = ConfigDict(extra="forbid")

    app: str
    display_name: str
    images: dict[str, ImageResponse]
    colors: dict[str, ColorOutput]

    @classmethod
    def from_output(
        cls, output: Output, app_id: str, run_id: str
    ) -> OutputResponse:
        """Project an `Output` onto the wire shape, minting a per-slot image
        URL that resolves to the image-streaming endpoint."""
        return cls(
            app=output.app,
            display_name=output.display_name,
            colors=output.colors,
            images={
                slot_id: ImageResponse(
                    prompt=img.prompt,
                    url=f"/apps/{app_id}/{run_id}/images/{slot_id}",
                )
                for slot_id, img in output.images.items()
            },
        )
