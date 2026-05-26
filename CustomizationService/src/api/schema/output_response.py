"""Wire shape the API returns: flat slot-keyed maps, never server paths.

`images`, `fonts` and `icons` each collapse to a `dict[str, str]` — slot
id maps directly to the value a client actually needs (a fetch URL for an
image or an SVG icon, a Google Fonts family name for a font). `lotties`
maps each slot to a `LottieWire` (a fetch URL for the baked `.json` plus
the playback metadata the client renders with — the colour is already
baked into the served file). The colour and text groups pass through
unchanged: they already carry exactly what the client consumes.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import ColorPalette, InsertionPoint, Output, TextSet


class LottieWire(BaseModel):
    """One lottie slot projected onto the wire: where to fetch the baked
    `.json` plus the playback metadata the client renders with. The colour
    is already baked into the served file, so there is no recolour map —
    the client plays the animation at ``speed`` and (reveal slots only)
    holds the revealed image for ``hold_seconds`` at the ``insertion_point``
    before both end. ``reveals`` / ``insertion_point`` / ``hold_seconds``
    are set only for reveal slots (lifted straight off ``LottieOutput``)."""

    model_config = ConfigDict(extra="forbid")

    url: str
    speed: float
    reveals: str | None = None
    insertion_point: InsertionPoint | None = None
    hold_seconds: float | None = None


class OutputResponse(BaseModel):
    """A run's `output.yaml` projected onto the wire. Images and icons
    become `slot -> URL`; fonts become `slot -> Google Fonts family`;
    lotties become `slot -> LottieWire`. The colour and text groups are
    byte-identical with disk."""

    model_config = ConfigDict(extra="forbid")

    app: str
    display_name: str
    images: dict[str, str]
    fonts: dict[str, str]
    icons: dict[str, str]
    lotties: dict[str, LottieWire]
    color_set: ColorPalette
    text_set: TextSet

    @classmethod
    def from_output(
        cls, output: Output, app_id: str, run_id: str
    ) -> OutputResponse:
        """Project an `Output` onto the wire shape, minting a per-slot
        fetch URL for each image, icon and lottie preset, and collapsing
        each font slot to its Google Fonts family."""
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
            icons={
                slot_id: f"/apps/{app_id}/{run_id}/icons/{slot_id}"
                for slot_id in output.icon_set.icons
            },
            lotties={
                slot_id: LottieWire(
                    url=f"/apps/{app_id}/{run_id}/lotties/{slot_id}",
                    speed=lottie.speed,
                    reveals=lottie.reveals,
                    insertion_point=lottie.insertion_point,
                    hold_seconds=lottie.hold_seconds,
                )
                for slot_id, lottie in output.lottie_set.lotties.items()
            },
        )
