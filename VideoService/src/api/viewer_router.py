"""Internal feed viewer — NOT the public read API.

One HTML page that lists every gym and shows BOTH its accepted (good) and
**rejected** feed side by side, for eyeballing scan quality. The public
``/gyms/{id}/videos`` endpoint deliberately never serves the rejected list; this
one does, so it is a **dev / validation surface** — keep it off any public
deployment.

- ``GET /viewer``      — the page (a static shell + JS that fetches the data below).
- ``GET /viewer/data`` — every gym with its good/rejected ids resolved to cards.

Gyms are read fresh on each ``/viewer/data`` call (so a re-scan shows on reload), and
only the videos those gyms actually reference (their good/rejected ids) are loaded —
threaded, never the whole pool.
"""

from __future__ import annotations

import logging
from pathlib import Path

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import HTMLResponse

from schema.video_output import VideoOutput
from src.api.errors import InvalidConfigError
from src.api.service.videos_service import videos_service
from src.classification.video_classifier import format_duration
from src.shared.util.video_id import video_id_from_url

logger = logging.getLogger(__name__)

viewer_router = APIRouter(tags=["viewer"])

VIEWER_HTML_PATH = Path(__file__).parent / "viewer.html"

def _card(video: VideoOutput) -> dict:
    """One video → the minimal fields a card needs (id drives the YouTube link)."""
    return {
        "id": video_id_from_url(video.url),
        "title": video.title,
        "channel": video.channel_name,
        "thumb": video.thumbnail_url or "",
        "dur": format_duration(video.duration_seconds),
        "tag": video.tag.value if video.tag else "",
    }


@viewer_router.get("/viewer", response_class=HTMLResponse, include_in_schema=False)
async def viewer_page() -> str:
    """The single-page feed viewer (HTML shell read from disk at serve time)."""
    return VIEWER_HTML_PATH.read_text(encoding="utf-8")


@viewer_router.get("/viewer/data", include_in_schema=False)
async def viewer_data() -> list[dict]:
    """Every gym with its accepted + rejected videos resolved to cards. Loads ONLY
    the videos a gym's good/rejected actually references (threaded — see
    ``VideosService.load_videos_by_id``), never the whole pool. Gyms are read fresh
    so a re-scan is reflected on reload."""
    try:
        service = videos_service()
        meta: list[tuple] = []
        referenced: set[str] = set()
        for gid in await service.list_gyms():
            gym = await service.load_gym(gid)
            good = list(gym.videos.good_video_ids)
            rejected = list(gym.videos.rejected_video_ids)
            referenced.update(good, rejected)
            meta.append((gym, good, rejected))
        by_id = await service.load_videos_by_id(referenced)
        return [
            {
                "id": gym.gym_id,
                "theme": gym.theme,
                "disciplines": ", ".join(g.value for g in gym.gym_type),
                "good": [_card(by_id[i]) for i in good if i in by_id],
                "rejected": [_card(by_id[i]) for i in rejected if i in by_id],
            }
            for gym, good, rejected in meta
        ]
    except InvalidConfigError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT, detail=str(exc)
        ) from None
    except Exception:
        logger.error("Failed to build viewer data", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build viewer data",
        ) from None
