"""API routes for the theme domain.

    * ``GET /api/v1/gyms/{gym_id}/showcase`` — a gym's branded class/reward
      cards + its saved theme design id (any employee OR any MEMBER of the
      gym may READ the theme, only owner/admin may CHANGE it via
      ``PUT /gyms/{id}/theme``).
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
    summary="Get a gym's showcase (branded class/reward cards + theme id)",
    description=(
        "The gym's branded class cards, points-store reward cards, and saved "
        "theme design id. ``classes`` / ``rewards`` are possibly-empty lists; "
        "``theme_design_id`` is null until the gym picks a theme. Readable by "
        "any employee of the gym (all four roles) AND any member of the gym — "
        "it is gym branding, not member data. Only owner/admin may CHANGE the "
        "theme (``PUT /gyms/{id}/theme``)."
    ),
    responses={
        200: {"description": "The gym's showcase"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not an employee or member of this gym"},
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
    """Return the gym's showcase: class cards, reward cards, theme id."""
    user_payload = auth.get_current_user(credentials)
    # Every employee role AND any member of the gym may READ its current
    # theme/showcase — this is gym branding, not member data, so a member
    # reaches it directly with only a gym_id (a deliberate exception to the
    # member-scoped-surface separation). Only owner/admin may CHANGE the
    # theme — that write is `PUT /gyms/{id}/theme`, still OWNER_ADMIN in
    # gyms_router.
    await auth.verify_gym_member_or_employee(gym_id, user_payload)

    try:
        classes, rewards, theme_design_id = await asyncio.gather(
            theme_showcase_service.load_showcase_classes(gym_id),
            theme_showcase_service.load_showcase_rewards(gym_id),
            theme_showcase_service.load_theme_design_id(gym_id),
        )
    except Exception:
        logger.error(
            "Failed to load gym showcase for %s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load gym showcase",
        ) from None
    return GymShowcase(
        gym_id=gym_id,
        classes=classes,
        rewards=rewards,
        theme_design_id=theme_design_id,
    )


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
