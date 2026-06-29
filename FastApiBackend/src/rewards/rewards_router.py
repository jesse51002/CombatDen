"""API routes for the rewards domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.rewards.schema.rewards_schema import (
    RedemptionHistoryResponse,
    RedemptionRequest,
    RedemptionResponse,
    RewardCreateRequest,
    RewardListResponse,
    RewardResponse,
    RewardUpdateRequest,
)
from src.rewards.service.rewards_redemption_service import (
    RewardsRedemptionService,
)
from src.rewards.service.rewards_service import RewardsService
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

rewards_router = APIRouter(
    prefix="/api/v1/rewards",
    tags=["rewards"],
)


@rewards_router.get(
    "/",
    response_model=RewardListResponse,
    summary="List rewards for a gym",
    responses={
        200: {"description": "Rewards listed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_rewards(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    rewards_service: RewardsService = Depends(Provide[DependencyInjector.rewards_service]),
    include_inactive: bool = False,
) -> RewardListResponse:
    """List rewards for a gym."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await rewards_service.list_rewards(gym_id, include_inactive=include_inactive)
    except Exception:
        logger.error(
            "Failed to list rewards: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list rewards",
        ) from None


@rewards_router.post(
    "/",
    response_model=RewardResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a reward",
    responses={
        201: {"description": "Reward created"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_reward(
    request: RewardCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    rewards_service: RewardsService = Depends(Provide[DependencyInjector.rewards_service]),
) -> RewardResponse:
    """Create a reward."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

    try:
        return await rewards_service.create_reward(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create reward: gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create reward",
        ) from None


@rewards_router.put(
    "/{reward_id}",
    response_model=RewardResponse,
    summary="Update a reward",
    responses={
        200: {"description": "Reward updated"},
        400: {"description": "Invalid update"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Reward not found"},
    },
)
@inject
async def update_reward(
    reward_id: UUID,
    request: RewardUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    rewards_service: RewardsService = Depends(Provide[DependencyInjector.rewards_service]),
) -> RewardResponse:
    """Update a reward."""
    user_payload = auth.get_current_user(credentials)

    try:
        existing = await rewards_service.get_reward(reward_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reward not found",
        ) from None

    await auth.verify_gym_admin_or_owner(existing.gym_id, user_payload)

    try:
        return await rewards_service.update_reward(reward_id, request.data)
    except ValueError as exc:
        msg = str(exc)
        if "not found" in msg.lower():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=msg,
            ) from None
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=msg,
        ) from None
    except Exception:
        logger.error(
            "Failed to update reward: reward_id=%s",
            reward_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update reward",
        ) from None


@rewards_router.delete(
    "/{reward_id}",
    response_model=RewardResponse,
    summary="Soft-delete a reward",
    description="Sets ``is_active = false`` on the reward.",
    responses={
        200: {"description": "Reward deactivated"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Reward not found"},
    },
)
@inject
async def deactivate_reward(
    reward_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    rewards_service: RewardsService = Depends(Provide[DependencyInjector.rewards_service]),
) -> RewardResponse:
    """Soft-delete a reward."""
    user_payload = auth.get_current_user(credentials)

    try:
        existing = await rewards_service.get_reward(reward_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reward not found",
        ) from None

    await auth.verify_gym_admin_or_owner(existing.gym_id, user_payload)

    try:
        return await rewards_service.deactivate_reward(reward_id)
    except Exception:
        logger.error(
            "Failed to deactivate reward: reward_id=%s",
            reward_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to deactivate reward",
        ) from None


@rewards_router.post(
    "/{reward_id}/redeem",
    response_model=RedemptionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Redeem a reward",
    description=(
        "Atomically debits ``members.points_balance`` and writes "
        "a row in ``member_reward_redemptions``. Rejected with 400 "
        "if the member has insufficient points or the reward is "
        "inactive."
    ),
    responses={
        201: {"description": "Redemption recorded"},
        400: {"description": "Insufficient points or inactive reward"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
    },
)
@inject
async def redeem_reward(
    reward_id: UUID,
    request: RedemptionRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
) -> RedemptionResponse:
    """Redeem a reward for a member."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await redemption_service.redeem(request.member_id, reward_id)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Redemption failed: member_id=%s, reward_id=%s",
            request.member_id,
            reward_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to redeem reward",
        ) from None


@rewards_router.get(
    "/redemptions",
    response_model=RedemptionHistoryResponse,
    summary="A member's reward redemption history",
    responses={
        200: {"description": "Redemption history retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member"},
    },
)
@inject
async def get_redemptions(
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
) -> RedemptionHistoryResponse:
    """Member's redemption history."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(member_id, user_payload)

    try:
        return await redemption_service.history(member_id)
    except Exception:
        logger.error(
            "Failed to retrieve redemptions: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve redemptions",
        ) from None


@rewards_router.get(
    "/{reward_id}",
    response_model=RewardResponse,
    summary="Get a single reward by id",
    responses={
        200: {"description": "Reward returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Reward not found"},
    },
)
@inject
async def get_reward_by_id(
    reward_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    rewards_service: RewardsService = Depends(Provide[DependencyInjector.rewards_service]),
) -> RewardResponse:
    """Get a single reward by id (gym-employee scoped)."""
    user_payload = auth.get_current_user(credentials)

    try:
        reward = await rewards_service.get_reward(reward_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reward not found",
        ) from None

    await auth.verify_gym_employee(reward.gym_id, user_payload)
    return reward
