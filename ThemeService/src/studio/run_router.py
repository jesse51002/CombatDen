"""The launch endpoints: start a run, stream it, poll it, fetch its images.

Three ways to watch one run, all fed by the same record list:

- ``GET /runs/{run_id}/events`` — Server-Sent Events. Plain
  ``StreamingResponse`` over an async generator; no ``sse-starlette``,
  because the browser's ``EventSource`` is built in and needs no npm
  dependency on the client either.
- ``GET /runs/{run_id}`` — the same records as one JSON snapshot, for a
  client that would rather poll.
- ``GET /runs/{run_id}/images/{slot_id}`` — the PNG a just-finished image
  node wrote, servable **while the run is still going**.

That last one exists because the read API cannot do it: its image endpoint
loads the run's ``output.yaml`` first (``OutputService.image_file``), and
that file is written only when the whole run finishes — so mid-run it 404s.
It also 307-redirects to the CDN by default, where a brand-new local run
does not exist. The studio serves the local file directly instead.
"""

from __future__ import annotations

import logging
from collections.abc import AsyncIterator

from fastapi import APIRouter, HTTPException, status
from fastapi.responses import FileResponse, StreamingResponse
from pydantic import ValidationError

from src.studio.errors import (
    RunInFlightError,
    RunNameTakenError,
    UnknownAppError,
    UnknownBriefError,
    UnknownRunError,
)
from src.studio.schema.launch_request import LaunchAccepted, LaunchRequest
from src.studio.schema.run_snapshot import RunSnapshot
from src.studio.service.run_launcher import run_launcher
from src.studio.service.run_registry import run_registry
from src.studio.service.run_reader import run_reader

logger = logging.getLogger(__name__)

run_router = APIRouter(prefix="/runs", tags=["runs"])

# Keep the stream raw all the way to the browser: no proxy buffering, no
# cache, no connection teardown between records.
_SSE_HEADERS = {
    "Cache-Control": "no-cache",
    "Connection": "keep-alive",
    "X-Accel-Buffering": "no",
}
# The generated PNG changes only when the slot is regenerated, and a demo
# wants the newest bytes the moment they land — so never cache it.
_IMAGE_HEADERS = {"Cache-Control": "no-store"}


@run_router.post(
    "",
    response_model=LaunchAccepted,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Start a pipeline run (returns immediately)",
    responses={
        202: {"description": "The run was accepted and is now generating"},
        404: {"description": "No such app, or no such saved brief"},
        409: {
            "description": (
                "A run is already in flight, or that run name already exists"
            )
        },
        422: {"description": "The request or the brief is invalid"},
    },
)
async def launch_run(request: LaunchRequest) -> LaunchAccepted:
    """Accept a brief + a NEW run name and start generating.

    Returns as soon as the run is registered — a full run takes minutes and
    spends real money, so nothing waits on it here. Watch the returned
    ``run_id`` via ``/runs/{run_id}/events``.
    """
    try:
        return await run_launcher().launch(request)
    except (UnknownAppError, UnknownBriefError) as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except RunInFlightError as exc:
        # Enough detail for the UI to name what is already running.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={
                "message": str(exc),
                "active_run_id": exc.run_id,
                "active_app_id": exc.app_id,
                "active_run_name": exc.run_name,
            },
        ) from None
    except RunNameTakenError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(exc)
        ) from None
    except ValidationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=exc.errors(include_url=False, include_context=False),
        ) from None


@run_router.get(
    "/active",
    response_model=RunSnapshot | None,
    summary="The run currently in flight, if any",
)
async def active_run() -> RunSnapshot | None:
    """The one in-flight run, or ``null``. Lets a page that loads fresh
    re-attach to a run already going instead of offering to start one."""
    return run_registry().active


@run_router.get(
    "/{run_id}",
    response_model=RunSnapshot,
    summary="One run's full state (the poll fallback)",
    responses={404: {"description": "No such run"}},
)
async def get_run(run_id: str) -> RunSnapshot:
    """The same records the SSE stream carries, as one snapshot."""
    try:
        return await run_registry().snapshot(run_id)
    except UnknownRunError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None


@run_router.get(
    "/{run_id}/events",
    summary="Stream one run's progress (Server-Sent Events)",
    responses={
        200: {
            "content": {"text/event-stream": {}},
            "description": (
                "Every record from index 0, then each new one as it lands; "
                "the stream ends after the terminal record"
            ),
        },
        404: {"description": "No such run"},
    },
)
async def stream_run(run_id: str) -> StreamingResponse:
    """Replay this run from index 0, then follow it live.

    Every frame is a default (unnamed) ``message`` event whose data is one
    ``RunRecord`` as JSON, with the record's index as the SSE ``id:``. One
    frame shape means a client needs only ``EventSource.onmessage``.

    **The client must call ``close()`` on the terminal record**
    (``kind == "settled"``): the server ends the stream there, and an
    ``EventSource`` that is still open will reconnect automatically — and
    be replayed from 0 again, forever. Replay is always from index 0 by
    design, so ``Last-Event-ID`` is deliberately ignored.
    """
    registry = run_registry()
    # Resolve the run before returning 200 — inside the generator a 404 is
    # no longer expressible.
    try:
        await registry.snapshot(run_id)
    except UnknownRunError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None

    async def frames() -> AsyncIterator[str]:
        async for record in registry.stream(run_id):
            yield (
                f"id: {record.index}\n"
                f"data: {record.model_dump_json()}\n\n"
            )

    return StreamingResponse(
        frames(), media_type="text/event-stream", headers=_SSE_HEADERS
    )


@run_router.get(
    "/{run_id}/images/{slot_id}",
    response_class=FileResponse,
    summary="Stream one image slot's PNG (works mid-run)",
    responses={
        200: {"content": {"image/png": {}}, "description": "The PNG bytes"},
        404: {
            "description": (
                "No such run/slot, or that slot's image has not been "
                "generated yet"
            )
        },
    },
)
async def get_run_image(run_id: str, slot_id: str) -> FileResponse:
    """The PNG for one slot of a studio run, straight off disk.

    Callable the moment a ``node_finished`` event arrives carrying that
    slot's ``image_slot`` — which is the point: the demo shows each image
    as it is produced, not after the whole run lands.
    """
    try:
        path = await run_reader().image_file(run_id, slot_id)
    except UnknownRunError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    return FileResponse(
        path, media_type="image/png", headers=_IMAGE_HEADERS
    )
