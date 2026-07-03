"""API routes for the rewards domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.rewards.schema.rewards_schema import (
    PendingRedemptionListResponse,
    RedeemForMemberRequest,
    RedemptionHistoryResponse,
    RedemptionRequest,
    RedemptionResponse,
    RedemptionTransitionResponse,
    RewardCreateRequest,
    RewardListResponse,
    RewardResponse,
    RewardUpdateRequest,
)
from src.rewards.service.rewards_redemption_service import (
    RedemptionAlreadyDecidedError,
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
    summary="Redeem a reward (member-initiated)",
    description=(
        "Atomically debits ``members.points_balance`` and writes "
        "a row in ``member_reward_redemptions`` with "
        "``status='pending'``.  Rejected with 400 if the member "
        "has insufficient points or the reward is inactive."
    ),
    responses={
        201: {"description": "Redemption recorded (pending)"},
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
    """Member-initiated redemption — creates a pending redemption."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_can_view_member(request.member_id, user_payload)

    try:
        return await redemption_service.redeem(
            request.member_id, reward_id, auto_approve=False
        )
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


@rewards_router.post(
    "/{reward_id}/redeem-for-member",
    response_model=RedemptionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Staff-initiated redemption for a member",
    description=(
        "Staff endpoint. If the member already has an OPEN PENDING "
        "redemption for this reward, the oldest one is APPROVED instead "
        "of debiting again (its points were taken at request time) — "
        "``override`` included. Otherwise a fresh approved redemption: "
        "``override=false`` → guarded debit; ``override=true`` → "
        "unguarded debit (drains to zero)."
    ),
    responses={
        201: {"description": "Redemption recorded (approved)"},
        400: {"description": "Insufficient points or inactive reward"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member's gym"},
    },
)
@inject
async def redeem_reward_for_member(
    reward_id: UUID,
    request: RedeemForMemberRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
) -> RedemptionResponse:
    """Staff-initiated redemption — always approved, optionally override points."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee_for_member(request.member_id, user_payload)

    try:
        return await redemption_service.redeem_for_member(
            request.member_id, reward_id, override=request.override
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Staff redemption failed: member_id=%s, reward_id=%s, override=%s",
            request.member_id,
            reward_id,
            request.override,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to redeem reward for member",
        ) from None


@rewards_router.get(
    "/redemptions/pending",
    response_model=PendingRedemptionListResponse,
    summary="Gym-wide pending redemption queue",
    responses={
        200: {"description": "Pending redemptions listed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_pending_redemptions(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
    limit: int = Query(default=100, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
) -> PendingRedemptionListResponse:
    """List a page of pending redemptions for a gym."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await redemption_service.list_pending(
            gym_id, limit=limit, offset=offset
        )
    except Exception:
        logger.error(
            "Failed to list pending redemptions: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list pending redemptions",
        ) from None


@rewards_router.post(
    "/redemptions/{redemption_id}/approve",
    response_model=RedemptionTransitionResponse,
    summary="Approve a pending redemption",
    responses={
        200: {"description": "Redemption approved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member's gym"},
        404: {"description": "Redemption not found"},
        409: {"description": "Redemption already decided"},
    },
)
@inject
async def approve_redemption(
    redemption_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
) -> RedemptionTransitionResponse:
    """Approve a pending redemption."""
    user_payload = auth.get_current_user(credentials)

    try:
        info = await redemption_service.get_redemption_for_auth(redemption_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Redemption not found",
        ) from None

    # The redemption row already carries its gym: authorize against that
    # directly — verify_gym_employee_for_member would pay a second members
    # round-trip just to re-derive the same gym_id.
    await auth.verify_gym_employee(UUID(str(info["gym_id"])), user_payload)

    try:
        return await redemption_service.approve(redemption_id)
    except RedemptionAlreadyDecidedError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to approve redemption: redemption_id=%s",
            redemption_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to approve redemption",
        ) from None


@rewards_router.post(
    "/redemptions/{redemption_id}/reject",
    response_model=RedemptionTransitionResponse,
    summary="Reject a pending redemption",
    responses={
        200: {"description": "Redemption rejected, points refunded"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this member's gym"},
        404: {"description": "Redemption not found"},
        409: {"description": "Redemption already decided"},
    },
)
@inject
async def reject_redemption(
    redemption_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
) -> RedemptionTransitionResponse:
    """Reject a pending redemption and refund the member's points."""
    user_payload = auth.get_current_user(credentials)

    try:
        info = await redemption_service.get_redemption_for_auth(redemption_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Redemption not found",
        ) from None

    # The redemption row already carries its gym: authorize against that
    # directly — verify_gym_employee_for_member would pay a second members
    # round-trip just to re-derive the same gym_id.
    await auth.verify_gym_employee(UUID(str(info["gym_id"])), user_payload)

    try:
        return await redemption_service.reject(redemption_id)
    except RedemptionAlreadyDecidedError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to reject redemption: redemption_id=%s",
            redemption_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to reject redemption",
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
