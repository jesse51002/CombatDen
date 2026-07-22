"""API routes for the member portal — the member-facing surface.

Everything under ``/api/v1/member`` is gated by ``Auth.verify_member_self``:
the caller's verified email must equal the target ``members`` row's email, a
CONFIRMED Supabase auth account must exist for it, and the member must belong
to the path gym. It grants staff NOTHING — a staff caller uses the CRM routes,
which are unchanged.

Three rules shape this router:

* **``member_id`` is never derived from the JWT.** One verified email
  legitimately matches SEVERAL member rows (a parent's inbox covers the whole
  family), so ``GET /api/v1/member/members`` hands the app its member rows and
  every other route takes the chosen ``member_id`` explicitly, re-checked by
  the gate.
* **Every gym-scoped route passes ``gym_id`` to the gate.** Without it one
  email reaches a same-named member at an unrelated gym.
* **No client-selectable gate semantics.** Anything that decides what a member
  may see or do is hardwired server-side: the reward redemption is always the
  pending (staff-approved) path, the video feed is always the served/accepted
  one, and the reward catalog is always the active one. No request schema here
  carries a mode flag.

Handlers are thin: every one delegates straight to the existing domain
service the CRM already uses, so the member surface can never drift from the
staff surface.
"""

import logging
from datetime import date, time
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import HTTPAuthorizationCredentials
from schema.video import VideoGenre

from src.checkin.schema.checkin_history_schema import (
    MemberClassHistoryResponse,
)
from src.checkin.schema.checkin_schema import StreakResponse
from src.checkin.schema.signup_schema import (
    SignupRemoveResponse,
    SignupResponse,
)
from src.checkin.service.checkin_history_service import CheckinHistoryService
from src.checkin.service.signup_service import SignupService
from src.checkin.service.streak_service import StreakService
from src.classes.schema.classes_crud_schema import (
    EffectiveClassInstanceListResponse,
)
from src.classes.service.classes_schedule_reader_service import (
    ClassesScheduleReaderService,
)
from src.core.dependencies import DependencyInjector
from src.member_portal.schema.member_portal_schema import (
    MemberPortalIdentityListResponse,
    MemberPortalProfile,
    MemberPortalSignupRequest,
)
from src.member_portal.service.member_portal_service import MemberPortalService
from src.rewards.schema.rewards_schema import (
    RedemptionHistoryResponse,
    RedemptionResponse,
    RewardListResponse,
)
from src.rewards.service.rewards_redemption_service import (
    RewardsRedemptionService,
)
from src.rewards.service.rewards_service import RewardsService
from src.shared.auth import Auth, security
from src.videos.schema.video_recs_schema import (
    MemberVideoRec,
    VideoRecClickResponse,
)
from src.videos.schema.videos_big_group import BigGroup
from src.videos.schema.videos_schema import GymVideosFeed
from src.videos.service.member_video_profile_refresh_runner import (
    MemberVideoProfileRefreshRunner,
)
from src.videos.service.member_video_profile_service import (
    MemberNotInGymError,
)
from src.videos.service.video_rec_click_service import RecNotFoundError
from src.videos.service.videos_service import VideosService

logger = logging.getLogger(__name__)

member_portal_router = APIRouter(
    prefix="/api/v1/member",
    tags=["member-portal"],
)

# Page size when the client doesn't ask — mobile-feed friendly, capped so one
# request can't pull a whole feed / history.
DEFAULT_PAGE_LIMIT = 20
MAX_PAGE_LIMIT = 100


# ── Identity ──────────────────────────────────────────────────────


@member_portal_router.get(
    "/members",
    response_model=MemberPortalIdentityListResponse,
    summary="The member rows bearing the caller's verified email",
    description=(
        "The member portal's entry point: the app calls this first to "
        "discover who and where the caller is, then passes the chosen "
        "``member_id`` + ``gym_id`` to every other route. Returns a LIST — "
        "``members.email`` carries no uniqueness constraint by design, so a "
        "parent's verified address matches every member row in the family, "
        "possibly across gyms. An email that is nobody's member returns an "
        "empty list (a valid state), not an error. Requires only a CONFIRMED "
        "auth account for the email claim (``verify_verified_account``); no "
        "``member_id`` exists to scope yet."
    ),
    responses={
        200: {"description": "The caller's member rows (possibly empty)"},
        401: {"description": "Not authenticated / no email claim"},
        403: {"description": "Email address is not verified"},
    },
)
@inject
async def list_my_members(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    portal_service: MemberPortalService = Depends(
        Provide[DependencyInjector.member_portal_service]
    ),
) -> MemberPortalIdentityListResponse:
    """Resolve the caller's verified email to their member rows."""
    user_payload = auth.get_current_user(credentials)
    email = await auth.verify_verified_account(user_payload)

    try:
        return await portal_service.list_members_for_email(email)
    except Exception:
        logger.error("Failed to list member rows for the caller", exc_info=True)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to list your member profiles",
        ) from None


# ── The member's own data ─────────────────────────────────────────


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}",
    response_model=MemberPortalProfile,
    summary="The member's own profile",
    description=(
        "The app's home-screen payload: identity + contact block, retention "
        "(points balance, class streak, last class, videos watched), rank "
        "progress, membership cards, and recent / pending reward "
        "redemptions. There is no separate points-balance or rank-progress "
        "route — both live here (``retention.points_balance`` / ``rank``). "
        "Gated by ``verify_member_self`` on the path gym."
    ),
    responses={
        200: {"description": "Profile returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_my_profile(
    gym_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    portal_service: MemberPortalService = Depends(
        Provide[DependencyInjector.member_portal_service]
    ),
) -> MemberPortalProfile:
    """The member's own profile block."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        return await portal_service.get_profile(member_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Member not found",
        ) from None
    except Exception:
        logger.error(
            "Failed to load member portal profile: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve your profile",
        ) from None


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}/streak",
    response_model=StreakResponse,
    summary="The member's own class attendance streak",
    description=(
        "Weeks of consecutive class attendance, bucketed in the gym's "
        "timezone. The same number the profile carries as "
        "``retention.class_streak_weeks`` — this cheap route exists so a home "
        "widget needn't pull the whole profile."
    ),
    responses={
        200: {"description": "Streak retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_my_streak(
    gym_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    streak_service: StreakService = Depends(
        Provide[DependencyInjector.streak_service]
    ),
) -> StreakResponse:
    """Weeks of consecutive class attendance."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        weeks = await streak_service.get_streak(member_id, gym_id)
    except Exception:
        logger.error(
            "Member-portal streak query failed: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve your streak",
        ) from None

    return StreakResponse(member_id=member_id, class_streak_weeks=weeks)


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}/class-history",
    response_model=MemberClassHistoryResponse,
    summary="The member's own class history (reservations, attendance, no-shows)",
    description=(
        "The member's OPEN reservations (occurrences not yet ended, soonest "
        "first, unpaginated) plus a newest-first page of their history — "
        "attended occurrences and no-shows (a reservation whose occurrence "
        "ended with no matching check-in)."
    ),
    responses={
        200: {"description": "History retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_my_class_history(
    gym_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    limit: int = Query(DEFAULT_PAGE_LIMIT, ge=1, le=MAX_PAGE_LIMIT),
    offset: int = Query(0, ge=0),
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    history_service: CheckinHistoryService = Depends(
        Provide[DependencyInjector.checkin_history_service]
    ),
) -> MemberClassHistoryResponse:
    """The member's own reservations + attended + no-show feed."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        return await history_service.get_history(
            member_id, gym_id, limit=limit, offset=offset
        )
    except Exception:
        logger.error(
            "Member-portal class-history query failed: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve your class history",
        ) from None


# ── The gym's schedule (read-only) ────────────────────────────────


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}/classes",
    response_model=EffectiveClassInstanceListResponse,
    summary="The gym's schedule board over a date window",
    description=(
        "The same computed schedule board the CRM reads: every non-deleted "
        "class expanded over ``[start_date, end_date]`` (cancelled days "
        "included and flagged), each occurrence carrying its resolved "
        "instructor, capacity, and sign-up / attendance counts. Read-only. "
        "Address any occurrence for a sign-up by its ORIGINAL slot — "
        "``class_id`` + ``original_date`` + ``original_time`` — never the "
        "post-reschedule ``class_date`` / ``resolved_class_time``. The gym is "
        "the member's own: the gate 403s a ``gym_id`` the member isn't in."
    ),
    responses={
        200: {"description": "Schedule board returned"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def list_my_gym_classes(
    gym_id: UUID,
    member_id: UUID,
    start_date: date,
    end_date: date,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    reader_service: ClassesScheduleReaderService = Depends(
        Provide[DependencyInjector.classes_schedule_reader_service]
    ),
) -> EffectiveClassInstanceListResponse:
    """The member's gym's schedule board across a date window."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        return await reader_service.list_effective_instances(
            gym_id, start_date, end_date
        )
    except Exception:
        logger.error(
            "Member-portal schedule board failed: gym_id=%s",
            gym_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load the class schedule",
        ) from None


# ── Reservations (the member's own) ───────────────────────────────


@member_portal_router.post(
    "/gyms/{gym_id}/members/{member_id}/signup",
    response_model=SignupResponse,
    summary="Reserve the member's own spot on a class occurrence",
    description=(
        "Reserves the member a spot on the occurrence addressed by "
        "``class_id`` + ``occurrence_date`` + ``occurrence_time`` (the "
        "ORIGINAL slot). A sign-up is a reservation, NOT attendance — "
        "``member_attendance`` is only ever written by a staff check-in, so a "
        "member cannot mark themselves present through this route. Rejected "
        "with 400 for a deleted / inactive class, a date that is not a real "
        "non-cancelled occurrence, or a full occurrence. Idempotent: a repeat "
        "returns the existing ``signup_id`` with ``already_signed_up = true`` "
        "and consumes no extra capacity."
    ),
    responses={
        200: {"description": "Reservation created (or an idempotent repeat)"},
        400: {"description": "Class full / deleted / inactive, or not an occurrence"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member or class not found"},
    },
)
@inject
async def create_my_signup(
    gym_id: UUID,
    member_id: UUID,
    request: MemberPortalSignupRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    signup_service: SignupService = Depends(
        Provide[DependencyInjector.signup_service]
    ),
    profile_refresh_runner: MemberVideoProfileRefreshRunner = Depends(
        Provide[DependencyInjector.member_video_profile_refresh_runner]
    ),
) -> SignupResponse:
    """Reserve the member their own spot on a class occurrence."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        result = await signup_service.create(
            member_id,
            gym_id,
            request.class_id,
            request.occurrence_date,
            request.occurrence_time,
        )
        # Same router-level composition as the staff sign-up: a booking is
        # fresh taste signal, fired best-effort so SignupService stays
        # decoupled from the videos domain. Never fails the booking.
        profile_refresh_runner.start(member_id, gym_id)
        return result
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
            "Member-portal sign-up failed: member_id=%s, class_id=%s",
            member_id,
            request.class_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record your reservation",
        ) from None


@member_portal_router.delete(
    "/gyms/{gym_id}/members/{member_id}/signup",
    response_model=SignupRemoveResponse,
    summary="Cancel the member's own reservation for a class occurrence",
    description=(
        "Deletes the member's own reservation for the occurrence addressed "
        "by its ORIGINAL slot. Returns ``removed = false`` with a 200 when "
        "there was no reservation. It removes only the reservation — an "
        "already-recorded check-in is staff-only to reverse."
    ),
    responses={
        200: {"description": "Removal result (removed true / false)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def remove_my_signup(
    gym_id: UUID,
    member_id: UUID,
    class_id: UUID,
    occurrence_date: date,
    occurrence_time: time,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    signup_service: SignupService = Depends(
        Provide[DependencyInjector.signup_service]
    ),
) -> SignupRemoveResponse:
    """Cancel the member's own reservation."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        return await signup_service.remove(
            member_id, gym_id, class_id, occurrence_date, occurrence_time
        )
    except Exception:
        logger.error(
            "Member-portal sign-up removal failed: member_id=%s, class_id=%s",
            member_id,
            class_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to cancel your reservation",
        ) from None


# ── Rewards ───────────────────────────────────────────────────────


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}/rewards",
    response_model=RewardListResponse,
    summary="The gym's ACTIVE reward catalog",
    description=(
        "What the member can spend points on, cheapest first. Only active "
        "rewards — ``include_inactive`` is not a member-selectable option, so "
        "a retired reward is never offered."
    ),
    responses={
        200: {"description": "Rewards listed"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def list_my_gym_rewards(
    gym_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    rewards_service: RewardsService = Depends(
        Provide[DependencyInjector.rewards_service]
    ),
) -> RewardListResponse:
    """The member's gym's active reward catalog."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        # include_inactive is hardwired False — never a client-selectable flag.
        return await rewards_service.list_rewards(gym_id, include_inactive=False)
    except Exception:
        logger.error(
            "Member-portal reward list failed: gym_id=%s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load rewards",
        ) from None


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}/redemptions",
    response_model=RedemptionHistoryResponse,
    summary="The member's own reward redemption history",
    responses={
        200: {"description": "Redemption history retrieved"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def get_my_redemptions(
    gym_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
) -> RedemptionHistoryResponse:
    """The member's own redemption history."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        return await redemption_service.history(member_id)
    except Exception:
        logger.error(
            "Member-portal redemption history failed: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to retrieve your redemptions",
        ) from None


@member_portal_router.post(
    "/gyms/{gym_id}/members/{member_id}/rewards/{reward_id}/redeem",
    response_model=RedemptionResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Request a reward redemption with the member's own points",
    description=(
        "Atomically debits the member's ``points_balance`` and records a "
        "PENDING redemption for staff to hand over and approve. "
        "``auto_approve`` is hardwired false — a member can never "
        "self-approve, and there is no ``override`` (comp) path here; both "
        "stay staff-only. Rejected with 400 on insufficient points or an "
        "inactive reward. The reward must belong to the member's own gym "
        "(404 otherwise)."
    ),
    responses={
        201: {"description": "Redemption recorded (pending staff approval)"},
        400: {"description": "Insufficient points or inactive reward"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found, or reward not at this gym"},
    },
)
@inject
async def redeem_my_reward(
    gym_id: UUID,
    member_id: UUID,
    reward_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    rewards_service: RewardsService = Depends(
        Provide[DependencyInjector.rewards_service]
    ),
    redemption_service: RewardsRedemptionService = Depends(
        Provide[DependencyInjector.rewards_redemption_service]
    ),
) -> RedemptionResponse:
    """Request a redemption with the member's own points (pending approval)."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    # Scope the reward to the member's own gym so a foreign reward_id reads as
    # what it is — a reward this member cannot see — instead of surfacing as a
    # generic redemption failure. The debit itself is safe either way: both
    # redeem statements now carry the same-gym predicate on the debiting CTE,
    # not only on the insert's join.
    try:
        reward = await rewards_service.get_reward(reward_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reward not found",
        ) from None
    if reward.gym_id != gym_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Reward not found",
        )

    try:
        # auto_approve is hardwired False — the member requests, staff approve.
        return await redemption_service.redeem(
            member_id, reward_id, auto_approve=False
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from None
    except Exception:
        logger.error(
            "Member-portal redemption failed: member_id=%s, reward_id=%s",
            member_id,
            reward_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to redeem the reward",
        ) from None


# ── Videos ────────────────────────────────────────────────────────


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}/videos",
    response_model=GymVideosFeed,
    summary="A page of the member's gym video feed, personalized",
    description=(
        "The gym's served feed (owner section merged with the latest "
        "completed run, enriched-and-accepted only), ranked against the "
        "member's own video-taste embedding when they have one. "
        "``video_type`` / ``big_group`` filter as expected and are mutually "
        "exclusive. The rejected list is NOT reachable here — ``rejected`` is "
        "hardwired false, so a member only ever sees what the gym serves."
    ),
    responses={
        200: {"description": "A page of the gym's feed"},
        400: {"description": "`video_type` and `big_group` are mutually exclusive"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found"},
    },
)
@inject
async def list_my_gym_videos(
    gym_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    video_type: VideoGenre | None = None,
    big_group: BigGroup | None = None,
    limit: int = Query(DEFAULT_PAGE_LIMIT, ge=1, le=MAX_PAGE_LIMIT),
    offset: int = Query(0, ge=0),
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> GymVideosFeed:
    """One page of the member's gym feed, personalized to their taste."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    if video_type is not None and big_group is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="video_type and big_group are mutually exclusive; pass at most one",
        )

    try:
        page, total = await videos_service.load_feed_page(
            gym_id,
            # rejected is hardwired False: the gym's rejected pile is staff-only.
            rejected=False,
            video_type=video_type,
            big_group=big_group,
            member_id=member_id,
            limit=limit,
            offset=offset,
        )
    except MemberNotInGymError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except Exception:
        logger.error(
            "Member-portal video feed failed: gym_id=%s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to load videos",
        ) from None

    return GymVideosFeed(total=total, limit=limit, offset=offset, videos=page)


@member_portal_router.get(
    "/gyms/{gym_id}/members/{member_id}/video-rec",
    response_model=MemberVideoRec,
    summary="The member's next rotating-category video recommendation",
    description=(
        "One recommendation at a time. The served genre rotates by the "
        "member's served-rec count, and within it the pick is the top of the "
        "served feed for that genre against the member's taste embedding. The "
        "pick is recorded and returned with its ``rec_id`` — post that back "
        "to the click route when the member opens it. 404 when no category "
        "yields a video."
    ),
    responses={
        200: {"description": "The member's next recommendation"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Member not found, or no recommendation available"},
    },
)
@inject
async def get_my_video_rec(
    gym_id: UUID,
    member_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> MemberVideoRec:
    """The member's own next recommendation."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        rec = await videos_service.get_video_rec(gym_id, member_id)
    except MemberNotInGymError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except Exception:
        logger.error(
            "Member-portal video rec failed: member_id=%s",
            member_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to build your recommendation",
        ) from None

    if rec is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="No video recommendation available for this member",
        )
    return rec


@member_portal_router.post(
    "/gyms/{gym_id}/members/{member_id}/video-rec/{rec_id}/click",
    response_model=VideoRecClickResponse,
    summary="Record the member opening their recommendation",
    description=(
        "Stamps a served recommendation as clicked (first click only — "
        "idempotent), logs a ``video_clicked`` activity, and fires a "
        "best-effort taste-profile refresh. A repeat click returns "
        "``clicked = false``. 404 when the rec is not this member's."
    ),
    responses={
        200: {"description": "Click recorded (or an idempotent repeat)"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not this member, or the member is at another gym"},
        404: {"description": "Recommendation not found for this member"},
    },
)
@inject
async def click_my_video_rec(
    gym_id: UUID,
    member_id: UUID,
    rec_id: UUID,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    videos_service: VideosService = Depends(
        Provide[DependencyInjector.videos_service]
    ),
) -> VideoRecClickResponse:
    """Record the member opening their own recommendation."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_member_self(member_id, user_payload, gym_id=gym_id)

    try:
        return await videos_service.record_rec_click(gym_id, member_id, rec_id)
    except RecNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from None
    except Exception:
        logger.error(
            "Member-portal rec click failed: member_id=%s, rec_id=%s",
            member_id,
            rec_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to record the recommendation click",
        ) from None
