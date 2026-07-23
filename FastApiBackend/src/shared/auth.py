"""Authentication and authorization for Supabase JWT tokens.

Identity is VERIFIED EMAIL, not an auth-user id. A gym is accessed by a
person whose Supabase JWT ``email`` claim (lowercased) matches a
``gym_employees`` row's ``email`` at that row's ``employee_type``. Stored
emails are lowercase, so the lowercased claim is an exact match.
An ``archived_at`` row is a soft-archived employee and grants NO access —
every authorization query filters ``archived_at IS NULL``.

**Verified means verified.** A matching row is not enough: every
identity-resolving query also requires a CONFIRMED Supabase auth account
for that email (``auth.users.email_confirmed_at IS NOT NULL``), so signing
up as ``owner@somegym.com`` without ever proving control of that inbox
grants nothing. The predicate is always a scalar ``EXISTS`` — never a JOIN,
because ``auth.users`` is unique on email only ``WHERE is_sso_user = false``
and a join can fan out.

The DB half of that guarantee only holds while GoTrue is actually mailing
confirmations: with ``enable_confirmations`` off, GoTrue stamps
``email_confirmed_at`` itself at signup. ``AuthSettingsGuard`` (run from the
app lifespan) reads GoTrue's own published config at startup and screams when
that is the case.

Trainers CAN log in now: a ``gym_employees`` row with any
``employee_type`` whose email matches the caller is that person's access
at that role. Which roles a given check accepts is passed explicitly as a
role set (``OWNER_ONLY`` / ``OWNER_ADMIN`` / ``STAFF`` / ``ALL_EMPLOYEES``
or any ``frozenset[EmployeeType]``), so a route documents exactly which
roles it admits.

Every check here is STAFF-scoped. ``verify_member_self`` is the one
member-facing primitive — the caller must BE the member — and nothing in
the CRM surface uses it; it exists for the member portal.

``Auth`` is a DI **Singleton shared by concurrent requests**: it holds no
request-scoped state, and every query opens its own session.
"""

import logging
from uuid import UUID

import jwt
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from schema.gym_employee import EmployeeType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.core.config import settings
from src.shared import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)

security = HTTPBearer()

# Role sets passed to the authorization checks. Each check admits the
# caller only when their (non-archived) ``gym_employees`` row's
# ``employee_type`` is in the set it is given.
OWNER_ONLY = frozenset({EmployeeType.owner})
OWNER_ADMIN = frozenset({EmployeeType.owner, EmployeeType.admin})
STAFF = frozenset(
    {EmployeeType.owner, EmployeeType.admin, EmployeeType.front_desk}
)
ALL_EMPLOYEES = frozenset(EmployeeType)


class Auth:
    """Handles Supabase JWT authentication and email-based gym access."""

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"
        self._jwks_client = jwt.PyJWKClient(jwks_url)
        self._db_pool = db_pool

    def get_current_user(
        self,
        credentials: HTTPAuthorizationCredentials,
    ) -> dict:
        """Validate Supabase JWT and return the decoded payload.

        Returns:
            Decoded JWT payload containing user info (sub, email, etc.).

        Raises:
            HTTPException: 401 if token is invalid or expired.
        """
        try:
            signing_key = self._jwks_client.get_signing_key_from_jwt(
                credentials.credentials,
            )
            payload = jwt.decode(
                credentials.credentials,
                signing_key.key,
                algorithms=["ES256"],
                audience="authenticated",
            )
            return payload
        except jwt.ExpiredSignatureError:
            logger.error("JWT token expired", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired",
            ) from None
        except jwt.InvalidTokenError:
            logger.error("Invalid JWT token", exc_info=True)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token",
            ) from None

    def require_email(self, user_payload: dict) -> str:
        """Return the caller's email claim, lowercased.

        Identity is the ``email`` claim (stored emails are lowercase, so
        the lowercased claim matches ``gym_employees.email`` /
        ``members.email`` exactly). This is the CLAIM only — that the
        address is confirmed is proven by the ``auth.users`` predicate
        every identity-resolving query carries.

        Public so a route that has ALREADY passed a role gate can read the
        caller's email without paying a second round-trip. A route with no
        prior gate must use ``verify_verified_account`` instead, which also
        proves the account is confirmed.

        Raises:
            HTTPException: 401 if the token carries no ``email`` claim.
        """
        email = user_payload.get("email")
        if not email:
            logger.error("JWT payload missing email claim")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token missing email claim",
            ) from None
        return email.lower()

    def require_sub(self, user_payload: dict) -> str:
        """Return the caller's ``sub`` claim — their ``auth.users`` id.

        Every identity-resolving query pins its confirmed-account ``EXISTS``
        to ``u.id = :caller_id`` so it proves the CALLER's OWN account is
        confirmed, not merely that SOME confirmed account holds that email.
        (`auth.users` is unique on email only ``WHERE is_sso_user = false``, so
        under SSO an unconfirmed password signup on an existing address could
        otherwise borrow a different confirmed row's verification.) The ``sub``
        claim is the caller's account id and is always present in a valid
        Supabase JWT; a missing one is a malformed token.

        Raises:
            HTTPException: 401 if the token carries no ``sub`` claim.
        """
        sub = user_payload.get("sub")
        if not sub:
            logger.error("JWT payload missing sub claim")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token missing sub claim",
            ) from None
        return sub

    async def verify_verified_account(self, user_payload: dict) -> str:
        """Return the caller's email, proven to back a CONFIRMED account.

        The standalone identity primitive for routes where the caller has
        no ``gym_employees`` row yet (creating their first gym), so no
        role check can carry the verified-account predicate for them.

        Returns:
            The caller's email, lowercased.

        Raises:
            HTTPException: 401 if the token has no ``email`` claim, 403 if
                no confirmed Supabase auth account exists for it.
        """
        email = self.require_email(user_payload)
        caller_id = self.require_sub(user_payload)

        async with self._db_pool.session() as session:
            row = (
                await session.execute(
                    text(load_sql(SQL_DIR / "auth_verified_account.sql")),
                    {"email": email, "caller_id": caller_id},
                )
            ).mappings().fetchone()

        if not row or not row["account_verified"]:
            logger.warning(
                "Unverified account attempted an action: email=%s",
                email,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Email address is not verified",
            ) from None

        return email

    async def _resolve_employee(
        self,
        gym_id: UUID,
        user_payload: dict,
        allowed: frozenset[EmployeeType],
    ) -> tuple[UUID, EmployeeType]:
        """Resolve the caller's active ``gym_employees`` row for a gym.

        Matches the lowercased email claim against a non-archived row at
        ``gym_id`` whose ``employee_type`` is in ``allowed`` AND which is
        backed by a confirmed ``auth.users`` account. The single query
        behind both ``verify_roles`` and ``get_employee_id``.

        Returns:
            ``(employee_id, employee_type)`` for the matched row.

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if no
                matching non-archived, verified row exists for the caller.
        """
        email = self.require_email(user_payload)
        caller_id = self.require_sub(user_payload)

        async with self._db_pool.session() as session:
            row = (
                await session.execute(
                    text(load_sql(SQL_DIR / "auth_resolve_employee.sql")),
                    {
                        "gym_id": str(gym_id),
                        "email": email,
                        "allowed_roles": [r.value for r in allowed],
                        "caller_id": caller_id,
                    },
                )
            ).mappings().fetchone()

        if not row:
            logger.warning(
                "Unauthorized gym access attempt: email=%s, gym_id=%s",
                email,
                gym_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to access this gym",
            ) from None

        return (
            UUID(str(row["employee_id"])),
            EmployeeType(row["employee_type"]),
        )

    async def verify_roles(
        self,
        gym_id: UUID,
        user_payload: dict,
        allowed: frozenset[EmployeeType],
    ) -> EmployeeType:
        """Verify the caller holds one of ``allowed`` roles at ``gym_id``.

        The CORE authorization check every other per-gym check delegates
        to. Matches the caller's verified email against a non-archived
        ``gym_employees`` row whose ``employee_type`` is in ``allowed``
        and whose email backs a confirmed Supabase auth account.

        Args:
            gym_id: The gym being accessed.
            user_payload: The decoded JWT payload (carries the ``email``
                claim used as identity).
            allowed: The roles that grant access (e.g. ``OWNER_ONLY``,
                ``OWNER_ADMIN``, ``STAFF``, ``ALL_EMPLOYEES``).

        Returns:
            The caller's matched ``employee_type``.

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if the
                caller holds no allowed role at the gym.
        """
        _, employee_type = await self._resolve_employee(
            gym_id, user_payload, allowed
        )
        return employee_type

    async def get_employee_id(
        self,
        gym_id: UUID,
        user_payload: dict,
        allowed: frozenset[EmployeeType],
    ) -> UUID:
        """Resolve the caller's ``employee_id`` for a gym.

        Used to stamp the operator/witness on records a staff member
        captures (e.g. a waiver signature). Same email-based
        authorization as ``verify_roles`` — the caller must hold one of
        ``allowed`` roles on a non-archived row — but returns the
        ``employee_id`` instead of only asserting access.

        ``allowed`` is REQUIRED and has no default, for the reason spelled
        out on ``verify_gym_employee_for_member``: a default silently gives
        an endpoint a role set nobody chose, and the wrong role set is
        invisible at the call site.

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if the
                caller holds no allowed role at the gym.
        """
        employee_id, _ = await self._resolve_employee(
            gym_id, user_payload, allowed
        )
        return employee_id

    async def verify_staff_principal(
        self,
        user_payload: dict,
        allowed: frozenset[EmployeeType],
    ) -> None:
        """Verify the caller holds one of ``allowed`` roles at ANY gym.

        The gym-AGNOSTIC staff gate, for endpoints that take no ``gym_id``
        (e.g. the shared image-upload proxy). Matches the caller's
        verified email against a non-archived ``gym_employees`` row at any
        gym whose ``employee_type`` is in ``allowed`` and which is backed
        by a confirmed auth account.

        ``allowed`` is REQUIRED and has no default — same reason as
        ``get_employee_id``.

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if the
                caller holds no allowed role at any gym.
        """
        email = self.require_email(user_payload)
        caller_id = self.require_sub(user_payload)

        async with self._db_pool.session() as session:
            row = (
                await session.execute(
                    text(load_sql(SQL_DIR / "auth_staff_principal.sql")),
                    {
                        "email": email,
                        "allowed_roles": [r.value for r in allowed],
                        "caller_id": caller_id,
                    },
                )
            ).mappings().fetchone()

        if not row:
            logger.warning(
                "Unauthorized staff-only action attempt: email=%s",
                email,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized: gym staff only",
            ) from None

    async def verify_gym_owner(
        self,
        gym_id: UUID,
        user_payload: dict,
    ) -> None:
        """Verify the caller is an OWNER of the gym.

        Gates owner-only actions (Stripe Connect onboarding). Admins,
        front-desk staff, and trainers are rejected even when they may
        otherwise access the gym. Thin wrapper over ``verify_roles`` with
        ``OWNER_ONLY``.

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if the
                caller is not an owner of the gym.
        """
        await self.verify_roles(gym_id, user_payload, OWNER_ONLY)

    async def verify_gym_admin_or_owner(
        self,
        gym_id: UUID,
        user_payload: dict,
    ) -> None:
        """Verify the caller is an ADMIN or OWNER of the gym.

        Gates gym-config writes (classes / rewards / discounts / plans
        create / update / delete). Mirrors the DB's
        ``is_gym_admin_or_owner`` RLS function at the API layer. Thin
        wrapper over ``verify_roles`` with ``OWNER_ADMIN``.

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if the
                caller is neither an admin nor an owner of the gym.
        """
        await self.verify_roles(gym_id, user_payload, OWNER_ADMIN)

    async def verify_member_self(
        self,
        member_id: UUID,
        user_payload: dict,
        *,
        gym_id: UUID | None = None,
    ) -> None:
        """Verify the caller IS this member.

        The one member-facing primitive — the member portal's gate. It
        grants NOTHING to staff; a staff-facing route uses
        ``verify_gym_employee_for_member`` instead. All three conditions
        must hold:

        1. The caller's lowercased ``email`` claim equals the ``members``
           row's ``email`` (lowercased). A parent's account therefore
           matches every member row bearing their email — the family case.
        2. A CONFIRMED Supabase auth account exists for that email, so an
           unverified signup on a member's address grants nothing.
        3. When ``gym_id`` is given, the member row's ``gym_id`` equals
           it. Pass it on every gym-scoped route: without it one email
           reaches a same-named member at an unrelated gym.

        Args:
            member_id: The member being accessed.
            user_payload: The decoded JWT payload.
            gym_id: Optional path gym the member must belong to. Omit only
                where the route carries no gym scope at all.

        Raises:
            HTTPException: 404 if the member does not exist, 401 if the
                token has no email claim, 403 if the caller is not that
                member, is unverified, or the member is at another gym.
        """
        email = self.require_email(user_payload)
        caller_id = self.require_sub(user_payload)

        async with self._db_pool.session() as session:
            row = (
                await session.execute(
                    text(load_sql(SQL_DIR / "auth_member_self.sql")),
                    {
                        "member_id": str(member_id),
                        "email": email,
                        "caller_id": caller_id,
                    },
                )
            ).mappings().fetchone()

        if not row:
            logger.error("Member not found: member_id=%s", member_id)
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Member not found",
            ) from None

        gym_matches = gym_id is None or UUID(str(row["gym_id"])) == gym_id
        if not (row["email_matches"] and row["account_verified"] and gym_matches):
            logger.warning(
                "Member-self access denied: email=%s, member_id=%s, gym_id=%s",
                email,
                member_id,
                gym_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized for this member",
            ) from None

    async def _get_member_gym_id(self, member_id: UUID) -> UUID:
        """Resolve a member's gym_id.

        Raises:
            HTTPException: 404 if the member is not found.
        """
        async with self._db_pool.session() as session:
            row = (
                await session.execute(
                    text(load_sql(SQL_DIR / "auth_member_gym_id.sql")),
                    {"member_id": str(member_id)},
                )
            ).mappings().fetchone()

        if not row:
            logger.error(
                "Member not found: member_id=%s",
                member_id,
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Member not found",
            ) from None

        return UUID(str(row["gym_id"]))

    async def verify_gym_employee_for_member(
        self,
        member_id: UUID,
        user_payload: dict,
        staff_roles: frozenset[EmployeeType],
        *,
        gym_id: UUID | None = None,
    ) -> None:
        """Verify the caller holds one of ``staff_roles`` at the member's
        gym.

        Staff-only: it grants the member themselves NOTHING. Resolves the
        member's gym then runs ``verify_roles`` with ``staff_roles``.
        This is the gate on EVERY member-scoped CRM route — reads and
        writes alike; a member-facing route uses ``verify_member_self``.

        ``staff_roles`` is REQUIRED on purpose: a default silently gave two
        video routes owner/admin gating nobody had chosen. Every call site
        states the role set it admits.

        ``gym_id`` reconciles a route that ALSO takes a gym in its body/path
        (check-in, sign-up) with the member: without it, the gate authorizes
        the caller at the MEMBER's gym while the handler stamps rows using
        the REQUEST's gym — so staff at gym A could write a row into gym B by
        pairing gym A's id with a gym-A member, or vice versa. When passed, the
        member's resolved gym must equal it (403 otherwise). Omit it only where
        the route carries no separate gym scope.

        Raises:
            HTTPException: 404 if the member is not found, 401 if the token
                has no email claim, 403 if the caller holds no allowed role
                at the member's gym, or the member is not in ``gym_id``.
        """
        member_gym_id = await self._get_member_gym_id(member_id)
        if gym_id is not None and member_gym_id != gym_id:
            logger.warning(
                "Member/gym mismatch: member_id=%s is at gym=%s, request "
                "gym=%s",
                member_id,
                member_gym_id,
                gym_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Member does not belong to this gym",
            ) from None
        await self.verify_roles(member_gym_id, user_payload, staff_roles)

    async def get_employee_id_for_member(
        self,
        member_id: UUID,
        user_payload: dict,
        allowed: frozenset[EmployeeType],
    ) -> UUID:
        """Resolve the caller's ``employee_id`` for a member's gym.

        The member-scoped variant of ``get_employee_id``. Both authorizes
        (the caller must hold one of ``allowed`` roles at the member's
        gym) and returns the ``employee_id`` — used to stamp the
        operator/witness when staff capture a signature in a member-scoped
        flow (the authorize-payer link flow). ``allowed`` is REQUIRED, for
        the same reason as above.

        Raises:
            HTTPException: 404 if the member is not found, 401 if the token
                has no email claim, 403 if the caller holds no allowed role
                at the member's gym.
        """
        gym_id = await self._get_member_gym_id(member_id)
        return await self.get_employee_id(gym_id, user_payload, allowed)
