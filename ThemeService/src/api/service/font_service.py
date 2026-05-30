"""FontService — the API-side delivery service for one font slot.

Resolves one font slot of one run into the delivery payload: family,
category, the Google Fonts CSS URL, and the per-variant font-file URLs
the frontend will fetch directly from ``fonts.gstatic.com``. The
Developer API returns TTF URLs (loadable by every consumer); the CSS2
endpoint is also included for web clients that prefer dropping in a
stylesheet link (Google serves woff2 to browsers under that URL).

The Google Fonts catalog is injected, not constructed inside — the API
process holds one process-scoped instance (see ``font_service_instance``
below) that's reused across every request, with the in-memory TTL
cache. Tests construct a ``FontService`` with a stub catalog directly,
no monkeypatching of module globals.
"""

from __future__ import annotations

import re
from urllib.parse import quote

from src.api.config import settings
from src.api.errors import NotFoundError
from src.api.schema.font_delivery import FontDeliveryResponse
from src.api.service.output_service import OutputService, output_service
from src.shared.interfaces.google_fonts_catalog import GoogleFontsCatalog
from src.shared.services.google_fonts_catalog import HttpxGoogleFontsCatalog

# snake_case ids (mirrors load_output's pattern).
_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")

# Standard Google Fonts CSS2 endpoint. The frontend can either hit this
# directly OR use the per-variant ``files`` URLs we return — both work,
# both go to Google's CDN.
GOOGLE_FONTS_CSS2_URL = "https://fonts.googleapis.com/css2"


class FontService:
    """Loads a run's ``output.yaml`` and lifts one slot's family into the
    deliverable Google Fonts payload.

    Both deps are injected — the OutputService that reads the run's
    artifact, and the Google Fonts catalog that resolves URLs — so tests
    can swap either for an in-memory stub without monkeypatching, and
    the API process can reuse one TTL-cached catalog across every
    request.
    """

    def __init__(
        self,
        *,
        catalog: GoogleFontsCatalog,
        outputs: OutputService,
    ) -> None:
        self._catalog = catalog
        self._outputs = outputs

    async def resolve(
        self, app_id: str, run_id: str, slot_id: str
    ) -> FontDeliveryResponse:
        """The on-Google-CDN font payload for one declared font slot.

        Three distinct 404 cases, each with a message that says which:

        * ``slot_id`` is malformed,
        * the slot is not declared in the run's ``output.yaml``,
        * the family the pipeline picked is no longer in the live
          Google Fonts catalog (rare — Google occasionally retires
          families).

        A missing / stale ``output.yaml`` still surfaces as 404 / 422
        from :meth:`OutputService.load`.
        """
        if not _ID_PATTERN.match(slot_id):
            raise NotFoundError(f"invalid font slot id {slot_id!r}")
        output = await self._outputs.load(app_id, run_id)
        slot = output.font_set.fonts.get(slot_id)
        if slot is None:
            raise NotFoundError(
                f"font slot {slot_id!r} is not declared in run "
                f"{app_id}/{run_id}"
            )
        entry = await self._catalog.lookup(slot.family)
        if entry is None:
            raise NotFoundError(
                f"font family {slot.family!r} (slot {slot_id!r}) is "
                "no longer in the Google Fonts catalog — re-run the "
                "pipeline to pick a current family"
            )
        return FontDeliveryResponse(
            family=entry.family,
            category=entry.category,
            css_url=f"{GOOGLE_FONTS_CSS2_URL}?family={quote(entry.family)}",
            variants=entry.files,
        )


def _build_default_catalog() -> GoogleFontsCatalog:
    """The production catalog: HTTPS hit to Google with the API key from
    Settings. Constructed lazily so a missing env var only fails when
    the font endpoint is actually hit, not at import time."""
    return HttpxGoogleFontsCatalog(
        api_key=settings.google_fonts_api_key,
        api_url=settings.google_fonts_api_url,
        ttl_seconds=settings.google_fonts_ttl_seconds,
        request_timeout_seconds=settings.google_fonts_request_timeout_seconds,
    )


# Process-scoped singleton the router depends on. Lazily-built: the
# catalog only instantiates on first access so importing this module
# doesn't already require ``GOOGLE_FONTS_API_KEY`` to be present.
_DEFAULT: FontService | None = None


def font_service() -> FontService:
    """The one process-scoped FontService, lazily built on first call."""
    global _DEFAULT
    if _DEFAULT is None:
        _DEFAULT = FontService(
            catalog=_build_default_catalog(),
            outputs=output_service(),
        )
    return _DEFAULT
