"""API routes for the growth (per-gym analytics) domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.growth.schema.growth_schema import GrowthResponse
from src.growth.service.growth_service import GrowthService
from src.shared.auth import OWNER_ADMIN, Auth, security

logger = logging.getLogger(__name__)

growth_router = APIRouter(
    prefix="/api/v1/growth",
    tags=["growth"],
)


@growth_router.get(
    "/",
    response_model=GrowthResponse,
    summary="Cached growth metrics for a gym",
    responses={
        200: {"description": "Growth metrics returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        500: {"description": "Failed to retrieve growth metrics"},
    },
)
@inject
async def get_growth(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    growth_service: GrowthService = Depends(Provide[DependencyInjector.growth_service]),
) -> GrowthResponse:
    """Serve a gym's cached growth metrics (recomputed hourly, never on read)."""
    user_payload = auth.get_current_user(credentials)
    # Owner/admin only — growth is gym analytics/revenue. This mirrors the CRM
    # role policy (canViewGrowth / canViewGymAnalytics are owner/admin), so
    # front desk, who never sees the Growth page or the revenue hero, also
    # can't pull the data by calling the endpoint directly.
    await auth.verify_roles(gym_id, user_payload, OWNER_ADMIN)

    try:
        return await growth_service.get_growth(gym_id)
    except Exception:
        logger.error(
            "Failed to retrieve growth metrics: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve growth metrics",
        ) from None
