"""Wire shape the API returns: flat slot-keyed maps, never server paths.

`images`, `fonts` and `icons` each collapse to a `dict[str, str]` — slot
id maps directly to the value a client actually needs (a fetch URL for an
image or an SVG icon, a Google Fonts family name for a font). The colour
and text groups pass through unchanged: they already carry exactly what the
client consumes.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict

from schema import ColorPalette, Output, TextSet
from src.core.asset_urls import cdn_url, icon_key, image_key


def _versioned(url: str, version: str) -> str:
    """Append the asset's content fingerprint as a cache-busting ``?v=``
    token. Empty version (legacy runs) → the URL is returned unchanged."""
    return f"{url}?v={version}" if version else url


def _image_url(app_id: str, run_id: str, slot_id: str, version: str, cdn: str) -> str:
    """Absolute CDN URL when a CDN base is configured (prod), else the relative
    container path (local dev). Both carry the ``?v=`` cache-buster."""
    if cdn:
        return cdn_url(cdn, image_key(app_id, run_id, slot_id), version)
    return _versioned(f"/apps/{app_id}/{run_id}/images/{slot_id}", version)


def _icon_url(app_id: str, run_id: str, slot_id: str, version: str, cdn: str) -> str:
    if cdn:
        return cdn_url(cdn, icon_key(app_id, run_id, slot_id), version)
    return _versioned(f"/apps/{app_id}/{run_id}/icons/{slot_id}", version)


class OutputResponse(BaseModel):
    """A run's `output.yaml` projected onto the wire. Images and icons
    become `slot -> URL`; fonts become `slot -> Google Fonts family`.
    The colour and text groups are byte-identical with disk."""

    model_config = ConfigDict(extra="forbid")

    app: str
    display_name: str
    design_name: str
    images: dict[str, str]
    fonts: dict[str, str]
    icons: dict[str, str]
    color_set: ColorPalette
    text_set: TextSet

    @classmethod
    def from_output(
        cls, output: Output, app_id: str, run_id: str, cdn_base_url: str = ""
    ) -> OutputResponse:
        """Project an `Output` onto the wire shape, minting a per-slot
        fetch URL for each image and icon, and collapsing each font slot
        to its Google Fonts family. ``cdn_base_url`` (when set) makes the
        image/icon URLs absolute CDN links; empty → relative container paths."""
        return cls(
            app=output.app,
            display_name=output.display_name,
            design_name=output.design_name,
            color_set=output.color_set,
            text_set=output.text_set,
            images={
                slot_id: _image_url(
                    app_id, run_id, slot_id, image.version, cdn_base_url
                )
                for slot_id, image in output.image_set.images.items()
            },
            fonts={
                slot_id: font.family
                for slot_id, font in output.font_set.fonts.items()
            },
            icons={
                slot_id: _icon_url(
                    app_id, run_id, slot_id, icon.version, cdn_base_url
                )
                for slot_id, icon in output.icon_set.icons.items()
            },
        )
