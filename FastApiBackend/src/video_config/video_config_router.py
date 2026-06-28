"""API routes for the video-config domain.

The LLM authoring surface for a gym's video configuration (its append-only spec —
keep/avoid criteria + search queries). All routes are gym-employee-gated and live
under ``/api/v1/gyms/{gym_id}/video-config``:

    * ``GET  …/video-config``                 — the gym's latest config version.
    * ``POST …/video-config/agent``           — one conversational turn (reply or
      a finished draft + the new serialized history).
    * ``POST …/video-config/generate-queries`` — the single-call query generator.
    * ``PUT  …/video-config``                 — confirm/save a draft (appends a new
      ``admin_update`` version).

The feed-learning refine route (``POST …/video-config/refine-from-feed``) is added
with the refiner service.
"""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security
from src.video_config.schema.video_config_schema import (
    GenerateQueriesRequest,
    GenerateQueriesResponse,
    VideoConfigAgentRequest,
    VideoConfigAgentResponse,
    VideoConfigDraft,
    VideoConfigView,
)
from src.video_config.service.video_config_service import (
    VideoConfigInputError,
    VideoConfigService,
)

logger = logging.getLogger(__name__)

video_config_router = APIRouter(tags=["video-config"])


@video_config_router.get(
    "/api/v1/gyms/{gym_id}/video-config",
    response_model=VideoConfigView,
    summary="Get a gym's latest video config",
)
@inject
async def get_video_config(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    service: VideoConfigService = Depends(
        Provide[DependencyInjector.video_config_service]
    ),
) -> VideoConfigView:
    """The gym's latest spec version. 404 when no config has been authored yet."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    config = await service.load_latest(gym_id)
    if config is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="This gym has no video config yet.",
        )
    return config


@video_config_router.post(
    "/api/v1/gyms/{gym_id}/video-config/agent",
    response_model=VideoConfigAgentResponse,
    summary="One conversational turn with the video-config agent",
)
@inject
async def video_config_agent_turn(
    gym_id: UUID,
    body: VideoConfigAgentRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    service: VideoConfigService = Depends(
        Provide[DependencyInjector.video_config_service]
    ),
) -> VideoConfigAgentResponse:
    """Run one turn: the agent replies with text (its next question) or a finished
    draft to review, plus the serialized history to send back next turn."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await service.agent_turn(gym_id, body)
    except Exception:
        logger.error("video-config agent turn failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The video-config agent failed to respond.",
        ) from None


@video_config_router.post(
    "/api/v1/gyms/{gym_id}/video-config/generate-queries",
    response_model=GenerateQueriesResponse,
    summary="Generate a gym's YouTube search queries",
)
@inject
async def generate_video_queries(
    gym_id: UUID,
    body: GenerateQueriesRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    service: VideoConfigService = Depends(
        Provide[DependencyInjector.video_config_service]
    ),
) -> GenerateQueriesResponse:
    """One structured LLM call → search queries spread across the video genres.
    Omitted inputs default to the gym's current spec."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        queries = await service.generate_queries(gym_id, body)
    except VideoConfigInputError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from None
    except Exception:
        logger.error("query generation failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to generate search queries.",
        ) from None
    return GenerateQueriesResponse(queries=queries)


@video_config_router.put(
    "/api/v1/gyms/{gym_id}/video-config",
    response_model=VideoConfigView,
    summary="Save a confirmed video-config draft",
)
@inject
async def save_video_config(
    gym_id: UUID,
    body: VideoConfigDraft,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    service: VideoConfigService = Depends(
        Provide[DependencyInjector.video_config_service]
    ),
) -> VideoConfigView:
    """Append a new spec version from a confirmed draft (``admin_update``)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    return await service.save_draft(gym_id, body)


@video_config_router.post(
    "/api/v1/gyms/{gym_id}/video-config/refine-from-feed",
    response_model=VideoConfigView,
    summary="Refine the video-config spec from manual feed curation signals",
)
@inject
async def refine_video_config_from_feed(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    service: VideoConfigService = Depends(
        Provide[DependencyInjector.video_config_service]
    ),
) -> VideoConfigView:
    """Fold unconsumed manual curation signals into a new ``feed_update`` spec
    version. 404 when there is no existing spec or no new signals to learn from."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        result = await service.refine_from_feed(gym_id)
    except Exception:
        logger.error("feed-refine failed", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The feed-learning refiner failed.",
        ) from None
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No new feed curation to learn from.",
        )
    return result
