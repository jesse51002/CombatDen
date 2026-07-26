"""API routes for the emails domain."""

import logging
from typing import Annotated
from uuid import UUID

from dependency_injector.wiring import Provide, inject
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPAuthorizationCredentials

from src.core.dependencies import DependencyInjector
from src.emails.schema.emails_schema import (
    MemberAppInviteEmail,
    SendEmailRequest,
    SendEmailResponse,
    StaffOnboardingEmail,
)
from src.emails.service.emails_log import EmailsLog
from src.emails.service.emails_runner import EmailsRunner
from src.emails.service.emails_service import EmailsService
from src.emails.service.emails_suppression import EmailsSuppression
from src.shared.auth import STAFF, Auth, security

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind, EmailSuppressionScope  # isort: skip

logger = logging.getLogger(__name__)

# Kinds staff may trigger by hand. An allowlist rather than "any EmailKind":
# a future kind is automatic-only until someone deliberately decides that
# re-sending it on demand is safe.
MANUAL_SEND_KINDS = frozenset(
    {EmailKind.staff_onboarding, EmailKind.member_app_invite}
)

# Per-subject, per-kind resend cap. Three in a trailing hour is generous for
# "they say they never got it" and still stops a staff member turning the
# button into a mail bomb (which is our sending reputation, not just theirs).
# The window the per-person cap counts over. The CAP ITSELF is a Settings
# field (`email_resend_max_per_hour`), injected below — it is an ops lever
# worth tuning without a deploy when a gym's onboarding day hits it.
RESEND_WINDOW_SECONDS = 3600

UNSUBSCRIBE_REASON = "unsubscribed"

UNSUBSCRIBED_PAGE = (
    "<!doctype html><html><head><meta charset='utf-8'>"
    "<title>Unsubscribed</title></head>"
    "<body style='font-family:system-ui,sans-serif;padding:48px;"
    "text-align:center'>"
    "<h1 style='font-size:20px'>You're unsubscribed</h1>"
    "<p style='color:#555'>You won't receive any more app invites or other "
    "promotional email from this gym. Account and access email still "
    "reaches you.</p></body></html>"
)

INVALID_TOKEN_PAGE = (
    "<!doctype html><html><head><meta charset='utf-8'>"
    "<title>Link expired</title></head>"
    "<body style='font-family:system-ui,sans-serif;padding:48px;"
    "text-align:center'>"
    "<h1 style='font-size:20px'>This link isn't valid</h1>"
    "<p style='color:#555'>The unsubscribe link was incomplete or has been "
    "altered. Reply to the email and we'll take you off the list.</p>"
    "</body></html>"
)

emails_router = APIRouter(
    prefix="/api/v1/emails",
    tags=["emails"],
)


@emails_router.post(
    "/send",
    response_model=SendEmailResponse,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Manually (re)send one of CombatDen's own emails",
    description=(
        "Claims an ``email_log`` row and fires the detached delivery. "
        "Carries NO recipient address — the address is resolved from the "
        "subject's own row, so this can never mail an arbitrary address "
        "from CombatDen's sending domain. Capped at 3 sends per subject "
        "per kind per hour (429 over the cap). Returns what actually "
        "happened: ``queued``, ``held`` (the kind is not enabled), "
        "``skipped_no_email``, or ``skipped_suppressed`` — never implying "
        "a send that did not happen. Staff-only (``STAFF`` at the gym)."
    ),
    responses={
        202: {"description": "Send claimed (or honestly skipped)"},
        400: {"description": "Unsupported kind or missing subject id"},
        401: {"description": "Not authenticated"},
        403: {"description": "Not authorized for this gym"},
        429: {"description": "Resend cap exceeded for this subject"},
    },
)
@inject
async def send_email(
    request: SendEmailRequest,
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    auth: Auth = Depends(Provide[DependencyInjector.auth]),
    emails_service: EmailsService = Depends(
        Provide[DependencyInjector.emails_service]
    ),
    emails_log: EmailsLog = Depends(Provide[DependencyInjector.emails_log]),
    emails_runner: EmailsRunner = Depends(
        Provide[DependencyInjector.emails_runner]
    ),
    resend_cap: int = Depends(
        Provide[DependencyInjector.emails_resend_cap]
    ),
) -> SendEmailResponse:
    """Claim + fire one manual send, honoring the per-subject resend cap."""
    user_payload = auth.get_current_user(credentials)
    await auth.verify_roles(request.gym_id, user_payload, STAFF)

    if request.kind not in MANUAL_SEND_KINDS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{request.kind} cannot be sent manually",
        )

    subject_id = _subject_id_for(request)

    try:
        recent = await emails_log.count_recent_for_subject(
            subject_id, request.kind, RESEND_WINDOW_SECONDS
        )
    except Exception:
        logger.error(
            "Failed to read the resend count: subject_id=%s, kind=%s",
            subject_id,
            request.kind,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send email",
        ) from None

    if recent >= resend_cap:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                f"Already sent {recent} of these in the last hour — "
                "try again later"
            ),
        )

    # The trailing-hour count doubles as the resend sequence, so the
    # idempotency key differs on every deliberate resend instead of
    # colliding with the original send and silently no-opping.
    payload = _payload_for(request, subject_id, resend_seq=recent)

    try:
        email_id, outcome = await emails_service.request_send(payload)
    except Exception:
        logger.error(
            "Failed to claim a manual send: gym_id=%s, kind=%s, subject=%s",
            request.gym_id,
            request.kind,
            subject_id,
            exc_info=True,
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to send email",
        ) from None

    if email_id is not None:
        emails_runner.start(email_id)
    return SendEmailResponse(outcome=outcome, email_id=email_id)


@emails_router.get(
    "/unsubscribe",
    response_class=HTMLResponse,
    summary="Unsubscribe from marketing email (PUBLIC, no auth)",
    description=(
        "The target of the unsubscribe link in every marketing email. "
        "PUBLIC by necessity — it is opened from a mail client with no "
        "session — so the signed token IS the authorization: it carries "
        "the address and gym, HMAC-signed, and nothing here is enumerable. "
        "Writes a ``marketing`` suppression, which never blocks "
        "transactional mail."
    ),
    responses={
        200: {"description": "Unsubscribed (or the link was invalid)"},
    },
)
@inject
async def unsubscribe(
    token: Annotated[str, Query(min_length=1, max_length=512)],
    suppression: EmailsSuppression = Depends(
        Provide[DependencyInjector.emails_suppression]
    ),
) -> HTMLResponse:
    """Verify the signed token and record a marketing suppression."""
    verified = suppression.verify_token(token)
    if verified is None:
        # 200, not 4xx: this page is read by a human in a mail client, and
        # every failure mode gets the same answer so a probe learns nothing.
        return HTMLResponse(content=INVALID_TOKEN_PAGE)

    email, gym_id = verified
    try:
        await suppression.suppress(
            email,
            gym_id,
            EmailSuppressionScope.marketing,
            UNSUBSCRIBE_REASON,
        )
    except Exception:
        logger.error(
            "Failed to record an unsubscribe: gym_id=%s", gym_id, exc_info=True
        )
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to unsubscribe",
        ) from None

    return HTMLResponse(content=UNSUBSCRIBED_PAGE)


def _subject_id_for(request: SendEmailRequest) -> UUID:
    """The subject id this kind requires, or a 400.

    Args:
        request: The validated send request.

    Returns:
        The employee or member id the kind is about.

    Raises:
        HTTPException: 400 when the id the kind needs is absent.
    """
    if request.kind is EmailKind.staff_onboarding:
        subject = request.employee_id
    else:
        subject = request.member_id
    if subject is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{request.kind} requires the subject's id",
        )
    return subject


def _payload_for(
    request: SendEmailRequest,
    subject_id: UUID,
    resend_seq: int,
) -> StaffOnboardingEmail | MemberAppInviteEmail:
    """Build the kind's typed payload — IDs only, never an address."""
    if request.kind is EmailKind.staff_onboarding:
        return StaffOnboardingEmail(
            kind=EmailKind.staff_onboarding,
            gym_id=request.gym_id,
            employee_id=subject_id,
            resend_seq=resend_seq,
        )
    return MemberAppInviteEmail(
        kind=EmailKind.member_app_invite,
        gym_id=request.gym_id,
        member_id=subject_id,
        resend_seq=resend_seq,
    )
