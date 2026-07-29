"""Wire shape the API returns: flat slot-keyed maps, never server paths.

Two shapes carry the same run, and the split is deliberate:

* `images`, `fonts` and `icons` are the FLAT projections — slot id maps
  directly to the one value a client needs (a fetch URL for an image or an
  SVG icon, a Google Fonts family name for a font). Both deployed clients
  parse these as `dict[str, str]` and DROP any entry whose value is not a
  bare string, so their shape is frozen: widening one would empty it in
  `ThemeFlutter` (and with it every gym's typography in `CRM` /
  `MobileApp`) silently, with a 200 on the wire.
* `color_set`, `font_set` and `text_set` pass the artifact's own output
  groups through unchanged — they already carry exactly what a client
  consumes. `image_set` is the one group that has to be projected instead
  (see `image_set_response.py`), because `ImageOutput` carries the
  producing machine's absolute `path` and the generation `prompt`.

Every flat map is derived from the group beside it inside `from_output`, so
the two statements of a value (`fonts[slot]` and `font_set.fonts[slot].family`;
`images[slot]` and `image_set.images[slot].url`) are one computation and
cannot drift apart.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from schema import ColorPalette, FontSet, Output, TextSet
from schema.output.format_set import FormatSet
from src.api.schema.image_set_response import ImageResponse, ImageSetResponse
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
    """A run's `output.yaml` projected onto the wire.

    `images` and `icons` become `slot -> URL`; `fonts` becomes `slot ->
    Google Fonts family`. `image_set` restates the images with the
    `complexity` tier a bare URL cannot carry. The colour, font and text
    groups are byte-identical with disk, so `font_set` carries each face's
    Google Fonts `category` and the prose the run wrote about it.

    `category` is the run's own classification bucket (the value the styles
    list filters on), a bare run-wide string exactly as on `Output` — never
    a group. It is `None` for a run produced before the classification node
    existed: the styles list refuses to LIST such a run, but this endpoint
    still serves it by id.

    `format_set` is the run's ARRANGEMENT decisions — one value per declared
    format slot, each the name of an enum value in the client's own layout
    vocabulary (`MobileApp/lib/core/formats/layout_formats.dart`, parsed by
    its `fromWire`). It passes through unchanged like the colour and text
    groups. It is EMPTY for a run produced before the format node existed,
    and for an app that declares no format slots; a client that gets nothing
    renders the arrangement it ships, so an absent pick is a non-event."""

    model_config = ConfigDict(extra="forbid")

    app: str
    display_name: str
    design_name: str
    category: str | None = None
    images: dict[str, str]
    fonts: dict[str, str]
    icons: dict[str, str]
    image_set: ImageSetResponse
    color_set: ColorPalette
    font_set: FontSet
    text_set: TextSet
    format_set: FormatSet = Field(default_factory=FormatSet)

    @classmethod
    def from_output(
        cls, output: Output, app_id: str, run_id: str, cdn_base_url: str = ""
    ) -> OutputResponse:
        """Project an `Output` onto the wire shape, minting a per-slot
        fetch URL for each image and icon, and collapsing each font slot
        to its Google Fonts family. ``cdn_base_url`` (when set) makes the
        image/icon URLs absolute CDN links; empty → relative container paths.

        The flat `images` / `fonts` maps are read back off the groups built
        here rather than recomputed, which is what makes the duplication on
        the wire a restatement instead of a second source of truth."""
        image_set = ImageSetResponse(
            images={
                slot_id: ImageResponse(
                    url=_image_url(
                        app_id, run_id, slot_id, image.version, cdn_base_url
                    ),
                    complexity=image.complexity,
                )
                for slot_id, image in output.image_set.images.items()
            }
        )
        return cls(
            app=output.app,
            display_name=output.display_name,
            design_name=output.design_name,
            category=output.category,
            color_set=output.color_set,
            font_set=output.font_set,
            text_set=output.text_set,
            format_set=output.format_set,
            image_set=image_set,
            images={
                slot_id: image.url for slot_id, image in image_set.images.items()
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
