"""API routes for the ranks domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from schema.gym_rank import RankPresetKind

from src.core.dependencies import DependencyInjector
from src.ranks.schema.ranks_schema import (
    AllPresetsGroupedResponse,
    FromPresetRequest,
    MembersInRankRequest,
    MembersInRankResponse,
    MembersReadyToPromoteRequest,
    MembersReadyToPromoteResponse,
    RankCreateRequest,
    RankEnabledRequest,
    RankEnabledResponse,
    RankListResponse,
    RankMemberResponse,
    RankPresetListResponse,
    RankPromoteMemberRequest,
    RankReorderRequest,
    RankResponse,
    RankSetMemberRequest,
    RankSubRankCountsResponse,
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

    "highest rank" and "already taken" → 409 (state conflict),
    "not found" → 404, anything else → 400.
    """
    message = str(exc)
    lowered = message.lower()
    if "highest rank" in lowered or "already taken" in lowered:
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
    """List a gym's ladder (one row per main rank) plus its sub_rank_type."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

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
        "Inserts a new main rank. If the gym has ``is_rank_enabled`` "
        "set, every rank-less member is backfilled to the lowest "
        "rank in the gym (which may be the rank just created)."
    ),
    responses={
        201: {"description": "Rank created"},
        400: {"description": "Invalid request"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        409: {"description": "Ladder position already taken"},
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
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

    try:
        return await ranks_service.create_rank(request)
    except ValueError as exc:
        raise _rank_http_error(exc) from None
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
        "``preset_kind`` into ``gym_ranks`` for the target gym and "
        "copies the preset's implied sub-rank type onto the gym. Uses "
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
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

    try:
        return await ranks_service.from_preset(request)
    except Exception:
        logger.error(
            "Failed to seed from preset: gym_id=%s, preset_kind=%s",
            request.gym_id,
            request.preset_kind,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to seed ranks from preset",
        ) from None


@ranks_router.get(
    "/presets",
    response_model=RankPresetListResponse,
    summary="Flat preset list for one preset kind",
    responses={
        200: {"description": "Presets listed"},
        401: {"description": "Not authenticated"},
    },
)
@inject
async def list_presets(
    preset_kind: RankPresetKind,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankPresetListResponse:
    """List rank presets for a single preset kind."""
    auth.get_current_user(credentials)

    try:
        return await ranks_service.list_presets(preset_kind)
    except Exception:
        logger.error(
            "Failed to list presets: preset_kind=%s",
            preset_kind,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list presets",
        ) from None


@ranks_router.get(
    "/presets/grouped",
    response_model=AllPresetsGroupedResponse,
    summary="All presets grouped by preset kind",
    description=(
        "Returns every ``rank_presets`` row, keyed by ``preset_kind``, "
        "as a flat list of main ranks in ladder order."
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
    """Return all presets grouped by preset kind."""
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
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

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
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

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
    summary="Promote a member to the next leaf",
    description=(
        "Advances the member one leaf up the gym's ordered ladder — "
        "the next sub-position within their current main rank, else "
        "the base leaf of the next main rank. A rank-less member is "
        "assigned the lowest leaf. Logs a ``rank_changed`` activity. "
        "Fails with 409 if the member is already at the highest leaf."
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
    """Promote a member one leaf up the ladder."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

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
        "Sets the member to an explicit leaf (correction / demotion "
        "/ assignment), or to no rank when ``rank_id`` is null. The "
        "target rank must belong to the member's gym; a rank with "
        "sub-ranks requires a ``sub_index`` in range, a subless rank "
        "forces it to null. Logs a ``rank_changed`` activity when the "
        "leaf changes."
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
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

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
    await auth.verify_gym_admin_or_owner(request.gym_id, user_payload)

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


# ---------- paginated member reads (declared before /{rank_id}) ----------


@ranks_router.get(
    "/ready-to-promote",
    response_model=MembersReadyToPromoteResponse,
    summary="Members closest to their next promotion",
    description=(
        "Paginated board of ranked, active-membership (not frozen), "
        "not-top-of-ladder members, ordered by how close they are to "
        "their next leaf (attendance since their last rank change over "
        "the per-step threshold)."
    ),
    responses={
        200: {"description": "Board returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
    },
)
@inject
async def list_ready_to_promote(
    gym_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    start_index: int = 0,
    count: int = 25,
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> MembersReadyToPromoteResponse:
    """List members closest to their next promotion."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_gym_admin_or_owner(gym_id, user_payload)

    try:
        return await ranks_service.list_ready_to_promote(
            MembersReadyToPromoteRequest(
                gym_id=gym_id,
                start_index=start_index,
                count=count,
            )
        )
    except Exception:
        logger.error(
            "Failed to list ready-to-promote: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list ready-to-promote members",
        ) from None


@ranks_router.get(
    "/{rank_id}/members",
    response_model=MembersInRankResponse,
    summary="Members currently on a rank",
    description=(
        "Paginated roster of members whose current rank is this one, "
        "ordered by percentage complete toward the next leaf "
        "(proportionally closest first); every member on the rank is "
        "returned."
    ),
    responses={
        200: {"description": "Members returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Rank not found"},
    },
)
@inject
async def list_members_in_rank(
    rank_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    start_index: int = 0,
    count: int = 25,
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> MembersInRankResponse:
    """List members currently on a given main rank."""
    user_payload = auth.get_current_user(credentials)

    try:
        rank = await ranks_service.get_rank(rank_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Rank not found",
        ) from None

    await auth.verify_gym_admin_or_owner(rank.gym_id, user_payload)

    try:
        return await ranks_service.list_members_in_rank(
            MembersInRankRequest(
                gym_id=rank.gym_id,
                rank_id=rank_id,
                start_index=start_index,
                count=count,
            )
        )
    except Exception:
        logger.error(
            "Failed to list members in rank: rank_id=%s",
            rank_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list members in rank",
        ) from None


@ranks_router.get(
    "/{rank_id}/sub-rank-counts",
    response_model=RankSubRankCountsResponse,
    summary="Member counts per sub-position for a rank",
    description=(
        "Total members currently on this main rank plus a SPARSE "
        "per-sub-index breakdown (only sub-positions with at least one "
        "member — the CRM fills 0 for empty slots from the rank's "
        "``sub_rank_count``). On a ``'none'`` gym members carry a NULL "
        "sub-index, so the breakdown is a single ``{null, total}`` row."
    ),
    responses={
        200: {"description": "Counts returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        404: {"description": "Rank not found"},
    },
)
@inject
async def count_members_by_sub_index(
    rank_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    ranks_service: RanksService = Depends(Provide[DependencyInjector.ranks_service]),
) -> RankSubRankCountsResponse:
    """Member counts per sub-position for a main rank.

    The gym is derived from the rank (resolved first — a clean 404 if the
    rank is missing), then the employee is verified against the RANK's gym;
    no client-supplied ``gym_id`` is trusted (mirrors ``/{rank_id}/members``).
    """
    user_payload = auth.get_current_user(credentials)

    try:
        rank = await ranks_service.get_rank(rank_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Rank not found",
        ) from None

    await auth.verify_gym_admin_or_owner(rank.gym_id, user_payload)

    try:
        return await ranks_service.count_members_by_sub_index(
            rank.gym_id,
            rank_id,
        )
    except Exception:
        logger.error(
            "Failed to count members by sub-index: rank_id=%s",
            rank_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to count members by sub-rank",
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

    await auth.verify_gym_admin_or_owner(rank.gym_id, user_payload)
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

    await auth.verify_gym_admin_or_owner(existing.gym_id, user_payload)

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
        "rank if one exists, else the next-higher rank, else NULL "
        "(pinned to the replacement's base leaf). Then hard-deletes "
        "the row from ``gym_ranks``."
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

    await auth.verify_gym_admin_or_owner(existing.gym_id, user_payload)

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
