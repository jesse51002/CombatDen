"""API routes for the ranks domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from schema.gym_rank import GymType

from src.core.dependencies import DependencyInjector
from src.ranks.schema.ranks_schema import (
    AllPresetsGroupedResponse,
    FromPresetRequest,
    RankCreateRequest,
    RankEnabledRequest,
    RankEnabledResponse,
    RankListResponse,
    RankMemberResponse,
    RankPresetListResponse,
    RankPromoteMemberRequest,
    RankRenameGroupRequest,
    RankReorderRequest,
    RankResponse,
    RankSetMemberRequest,
    RankUpdateRequest,
)
from src.ranks.service.ranks_service import RanksService
from src.shared.auth import Auth, security

logger = logging.getLogger(__name__)

ranks_router = APIRouter(
    prefix="/api/v1/ranks",
    tags=["ranks"],
)


def _rank_http_error(exc: ValueError) -> HTTPException:
    """Map a ranks-domain ValueError to its HTTP status.

    "highest rank" → 409 (state conflict), "not found" → 404,
    anything else → 400.
    """
    message = str(exc)
    lowered = message.lower()
    if "highest rank" in lowered:
        code = status.HTTP_409_CONFLICT
    elif "not found" in lowered:
        code = status.HTTP_404_NOT_FOUND
    else:
        code = status.HTTP_400_BAD_REQUEST
    return HTTPException(status_code=code, detail=message)


# ---------- list / create (collection) ----------


@ranks_router.get(
    "/",
    response_model=RankListResponse,
    summary="List ranks for a gym",
    responses={
        200: {"description": "Ranks listed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_ranks(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankListResponse:
    """List all ranks for a gym, ordered by main then sub."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await ranks_service.list_ranks(gym_id)
    except Exception:
        logger.error(
            "Failed to list ranks: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list ranks",
        ) from None


@ranks_router.post(
    "/",
    response_model=RankResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a rank",
    description=(
        "Inserts a new rank. If the gym has ``is_rank_enabled`` "
        "set, every rank-less member is backfilled to the lowest "
        "rank in the gym (which may be the rank just created)."
    ),
    responses={
        201: {"description": "Rank created"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def create_rank(
    request: RankCreateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankResponse:
    """Create a rank."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await ranks_service.create_rank(request)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Failed to create rank: gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to create rank",
        ) from None


# ---------- preset flows (declared before /{rank_id}) ----------


@ranks_router.post(
    "/from-preset",
    response_model=RankListResponse,
    summary="Seed gym ranks from a preset ladder",
    description=(
        "Bulk-clones every ``rank_presets`` row of the given "
        "``gym_type`` into ``gym_ranks`` for the target gym. Uses "
        "``ON CONFLICT DO NOTHING`` so re-running on the same gym "
        "is idempotent. Triggers the lowest-rank backfill if the "
        "gym has ``is_rank_enabled`` set."
    ),
    responses={
        200: {"description": "Ranks seeded; current list returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def seed_from_preset(
    request: FromPresetRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankListResponse:
    """Seed gym ranks from a preset ladder."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await ranks_service.from_preset(request)
    except Exception:
        logger.error(
            "Failed to seed from preset: gym_id=%s, gym_type=%s",
            request.gym_id,
            request.gym_type,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to seed ranks from preset",
        ) from None


@ranks_router.get(
    "/presets",
    response_model=RankPresetListResponse,
    summary="Flat preset list for one gym_type",
    responses={
        200: {"description": "Presets listed"},
        401: {"description": "Not authenticated"},
    },
)
@inject
async def list_presets(
    gym_type: GymType,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankPresetListResponse:
    """List rank presets for a single gym_type."""
    auth.get_current_user(credentials)

    try:
        return await ranks_service.list_presets(gym_type)
    except Exception:
        logger.error(
            "Failed to list presets: gym_type=%s",
            gym_type,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list presets",
        ) from None


@ranks_router.get(
    "/presets/grouped",
    response_model=AllPresetsGroupedResponse,
    summary="All presets grouped by gym_type and main rank",
    description=(
        "Returns every ``rank_presets`` row, keyed by ``gym_type``, "
        "with sub-ranks nested under their main rank in order."
    ),
    responses={
        200: {"description": "Grouped presets returned"},
        401: {"description": "Not authenticated"},
    },
)
@inject
async def get_presets_grouped(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> AllPresetsGroupedResponse:
    """Return all presets grouped by gym_type and main rank."""
    auth.get_current_user(credentials)

    try:
        return await ranks_service.get_all_presets_grouped()
    except Exception:
        logger.error("Failed to get grouped presets", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get grouped presets",
        ) from None


# ---------- rank-enabled toggle (declared before /{rank_id}) ----------


@ranks_router.get(
    "/enabled",
    response_model=RankEnabledResponse,
    summary="Get the gym's rank-enabled state",
    responses={
        200: {"description": "Rank-enabled state returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Gym not found"},
    },
)
@inject
async def get_rank_enabled(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankEnabledResponse:
    """Get the gym's rank-enabled state."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        return await ranks_service.get_rank_enabled(gym_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Gym not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to get rank-enabled: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to get rank-enabled",
        ) from None


@ranks_router.put(
    "/enabled",
    response_model=RankEnabledResponse,
    summary="Set the gym's rank-enabled state",
    description=(
        "Flips ``gyms.is_rank_enabled``. On a false→true "
        "transition, backfills every rank-less member to the "
        "lowest rank in the gym (no-op if the gym has no ranks). "
        "Disabling never touches member rank data."
    ),
    responses={
        200: {"description": "Rank-enabled state updated"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Gym not found"},
    },
)
@inject
async def set_rank_enabled(
    request: RankEnabledRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankEnabledResponse:
    """Set the gym's rank-enabled state."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await ranks_service.set_rank_enabled(request)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Gym not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to set rank-enabled: gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to set rank-enabled",
        ) from None


# ---------- member rank changes + reorder (before /{rank_id}) ----------


@ranks_router.post(
    "/promote-member",
    response_model=RankMemberResponse,
    summary="Promote a member to the next rank",
    description=(
        "Advances the member one step up the gym's ordered ladder. "
        "A rank-less member is assigned the lowest rank. Logs a "
        "``rank_changed`` activity. Fails with 409 if the member is "
        "already at the highest rank."
    ),
    responses={
        200: {"description": "Member promoted"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Member not found"},
        409: {"description": "Member already at the highest rank"},
    },
)
@inject
async def promote_member(
    request: RankPromoteMemberRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankMemberResponse:
    """Promote a member one step up the ladder."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await ranks_service.promote_member(request)
    except ValueError as exc:
        raise _rank_http_error(exc) from None
    except Exception:
        logger.error(
            "Failed to promote member: gym_id=%s, member_id=%s",
            request.gym_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to promote member",
        ) from None


@ranks_router.post(
    "/set-member-rank",
    response_model=RankMemberResponse,
    summary="Set a member's rank explicitly",
    description=(
        "Sets the member to an explicit rank (correction / demotion "
        "/ assignment), or to no rank when ``rank_id`` is null. The "
        "target rank must belong to the member's gym. Logs a "
        "``rank_changed`` activity when the rank changes."
    ),
    responses={
        200: {"description": "Member rank set"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Member or rank not found"},
    },
)
@inject
async def set_member_rank(
    request: RankSetMemberRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankMemberResponse:
    """Set a member's rank explicitly."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await ranks_service.set_member_rank(request)
    except ValueError as exc:
        raise _rank_http_error(exc) from None
    except Exception:
        logger.error(
            "Failed to set member rank: gym_id=%s, member_id=%s",
            request.gym_id,
            request.member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to set member rank",
        ) from None


@ranks_router.post(
    "/reorder",
    response_model=RankListResponse,
    summary="Reorder a gym's rank ladder",
    description=(
        "Applies a full new ordering for the gym's ENTIRE ladder — "
        "every rank exactly once, target positions unique — in one "
        "atomic two-phase update, so the unique-order constraint is "
        "never transiently violated. A payload that misses ranks, "
        "names unknown ranks, or repeats a position is rejected with "
        "400. Returns the reordered ladder."
    ),
    responses={
        200: {"description": "Ranks reordered; list returned"},
        400: {"description": "Invalid ordering"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def reorder_ranks(
    request: RankReorderRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankListResponse:
    """Reorder a gym's rank ladder atomically."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await ranks_service.reorder_ranks(request)
    except ValueError as exc:
        raise _rank_http_error(exc) from None
    except Exception:
        logger.error(
            "Failed to reorder ranks: gym_id=%s",
            request.gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to reorder ranks",
        ) from None


@ranks_router.put(
    "/rename-group",
    response_model=RankListResponse,
    summary="Rename a whole main-rank group",
    description=(
        "Renames every sub-rank row sharing the group's "
        "``main_rank_num_order`` in one atomic UPDATE "
        "(``main_name`` is denormalized per row). Returns the "
        "updated ladder."
    ),
    responses={
        200: {"description": "Group renamed; ladder returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Rank group not found"},
    },
)
@inject
async def rename_group(
    request: RankRenameGroupRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankListResponse:
    """Rename a whole main-rank group atomically."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(request.gym_id, user_payload)

    try:
        return await ranks_service.rename_group(request)
    except ValueError as exc:
        raise _rank_http_error(exc) from None
    except Exception:
        logger.error(
            "Failed to rename rank group: gym_id=%s, main_order=%s",
            request.gym_id,
            request.main_rank_num_order,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to rename rank group",
        ) from None


@ranks_router.delete(
    "/group",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Hard-delete a whole main-rank group",
    description=(
        "Reassigns every member on any of the group's sub-ranks to "
        "the nearest lower group's highest sub-rank (else the "
        "nearest higher group's lowest, else NULL), then deletes "
        "every row of the group — one transaction."
    ),
    responses={
        204: {"description": "Group deleted"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Rank group not found"},
    },
)
@inject
async def delete_group(
    gym_id: UUID,
    main_rank_num_order: int,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> None:
    """Hard-delete a main-rank group with downgrade-first semantics."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_employee(gym_id, user_payload)

    try:
        await ranks_service.delete_group(gym_id, main_rank_num_order)
    except ValueError as exc:
        raise _rank_http_error(exc) from None
    except Exception:
        logger.error(
            "Failed to delete rank group: gym_id=%s, main_order=%s",
            gym_id,
            main_rank_num_order,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete rank group",
        ) from None


# ---------- single-rank read / update / delete ----------


@ranks_router.get(
    "/{rank_id}",
    response_model=RankResponse,
    summary="Get a rank by id",
    responses={
        200: {"description": "Rank returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Rank not found"},
    },
)
@inject
async def get_rank(
    rank_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankResponse:
    """Get a rank by id."""
    user_payload = auth.get_current_user(credentials)

    try:
        rank = await ranks_service.get_rank(rank_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Rank not found",
        ) from None

    await auth.verify_gym_employee(rank.gym_id, user_payload)
    return rank


@ranks_router.put(
    "/{rank_id}",
    response_model=RankResponse,
    summary="Update a rank",
    responses={
        200: {"description": "Rank updated"},
        400: {"description": "Invalid update"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Rank not found"},
    },
)
@inject
async def update_rank(
    rank_id: UUID,
    request: RankUpdateRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankResponse:
    """Update a rank."""
    user_payload = auth.get_current_user(credentials)

    try:
        existing = await ranks_service.get_rank(rank_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Rank not found",
        ) from None

    await auth.verify_gym_employee(existing.gym_id, user_payload)

    try:
        return await ranks_service.update_rank(rank_id, request.data)
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
            "Failed to update rank: rank_id=%s",
            rank_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to update rank",
        ) from None


@ranks_router.delete(
    "/{rank_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Hard-delete a rank",
    description=(
        "Reassigns every member with this rank to the next-lower "
        "rank if one exists, else the next-higher rank, else NULL. "
        "Then hard-deletes the row from ``gym_ranks``."
    ),
    responses={
        204: {"description": "Rank deleted"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Rank not found"},
    },
)
@inject
async def delete_rank(
    rank_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> None:
    """Hard-delete a rank with downgrade-first semantics."""
    user_payload = auth.get_current_user(credentials)

    try:
        existing = await ranks_service.get_rank(rank_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Rank not found",
        ) from None

    await auth.verify_gym_employee(existing.gym_id, user_payload)

    try:
        await ranks_service.delete_rank(rank_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Rank not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to delete rank: rank_id=%s",
            rank_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to delete rank",
        ) from None
