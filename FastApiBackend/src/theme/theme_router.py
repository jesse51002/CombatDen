"""API routes for the theme domain.

    * ``GET /api/v1/gyms/{gym_id}/showcase`` — a gym's branded class/reward
      cards (admin/owner gated).
    * ``GET /api/v1/theme/showcase-defaults`` — category-keyed static demo
      class/reward cards for the standalone theme browser (PUBLIC).
"""

import asyncio
import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.shared.auth import Auth, security
from src.theme.schema.theme_schema import GymShowcase, ShowcaseDefaults
from src.theme.service.theme_showcase_defaults_service import (
    ThemeShowcaseDefaultsService,
)
from src.theme.service.theme_showcase_service import ThemeShowcaseService

logger = logging.getLogger(__name__)

theme_router = APIRouter(tags=["theme"])


@theme_router.get(
    "/api/v1/gyms/{gym_id}/showcase",
    response_model=GymShowcase,
    summary="Get a gym's showcase (branded class/reward cards)",
    description=(
        "The gym's branded class cards and points-store reward cards. "
        "``classes`` / ``rewards`` are possibly-empty lists. "
        "Admin/owner gated."
    ),
    responses={
        200: {"description": "The gym's showcase"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee of this gym"},
    },
)
@inject
async def get_gym_showcase(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    theme_showcase_service: ThemeShowcaseService = Depends(
        Provide[DependencyInjector.theme_showcase_service]
    ),
) -> GymShowcase:
    """Return the gym's showcase: its class cards and reward cards."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

    try:
        classes, rewards = await asyncio.gather(
            theme_showcase_service.load_showcase_classes(gym_id),
            theme_showcase_service.load_showcase_rewards(gym_id),
        )
    except Exception:
        logger.error(
            "Failed to load gym showcase for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym showcase",
        ) from None
    return GymShowcase(gym_id=gym_id, classes=classes, rewards=rewards)


@theme_router.get(
    "/api/v1/theme/showcase-defaults",
    response_model=ShowcaseDefaults,
    summary="Category-keyed demo showcase cards (public)",
    description=(
        "Static, bundled demo class and reward cards keyed by showcase "
        "category, for the standalone theme browser. **PUBLIC — no auth.** "
        "Serves only static bundled demo content (no gym or member data), "
        "so it is safe to expose unauthenticated; the browser has no login."
    ),
    responses={
        200: {"description": "The category-keyed demo showcase cards"},
    },
)
@inject
async def get_showcase_defaults(
    theme_showcase_defaults_service: ThemeShowcaseDefaultsService = Depends(
        Provide[DependencyInjector.theme_showcase_defaults_service]
    ),
) -> ShowcaseDefaults:
    """Return the category-keyed static demo showcase cards (public)."""
    try:
        return await theme_showcase_defaults_service.load_defaults()
    except Exception:
        logger.error("Failed to load showcase defaults", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load showcase defaults",
        ) from None
