"""Authentication and authorization for Supabase JWT tokens.

Identity is VERIFIED EMAIL, not an auth-user id. A gym is accessed by a
person whose Supabase JWT ``email`` claim (lowercased) matches a
``gym_employees`` row's ``email`` at that row's ``employee_type``. Stored
emails are lowercase, so the lowercased claim is an exact ``.eq`` match.
An ``archived_at`` row is a soft-archived employee and grants NO access —
every authorization query filters ``archived_at IS NULL``.

Trainers CAN log in now: a ``gym_employees`` row with any
``employee_type`` whose email matches the caller is that person's access
at that role. Which roles a given check accepts is passed explicitly as a
role set (``OWNER_ONLY`` / ``OWNER_ADMIN`` / ``STAFF`` / ``ALL_EMPLOYEES``
or any ``frozenset[EmployeeType]``), so a route documents exactly which
roles it admits.
"""

import logging
from uuid import UUID

import jwt
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from schema.gym_employee import EmployeeType

import src.shared.db_schema_path  # noqa: F401
from src.core.config import settings
from src.shared.database import SupabaseClient

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

    def __init__(self, supabase: SupabaseClient) -> None:
        jwks_url = f"{settings.supabase_url}/auth/v1/.well-known/jwks.json"
        self._jwks_client = jwt.PyJWKClient(jwks_url)
        self._supabase = supabase

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

    def _require_email(self, user_payload: dict) -> str:
        """Return the caller's verified email claim, lowercased.

        Identity is the ``email`` claim (stored emails are lowercase, so
        the lowercased claim matches ``gym_employees.email`` /
        ``members.email`` exactly).

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

    async def _resolve_employee(
        self,
        gym_id: UUID,
        user_payload: dict,
        allowed: frozenset[EmployeeType],
    ) -> tuple[UUID, EmployeeType]:
        """Resolve the caller's active ``gym_employees`` row for a gym.

        Matches the lowercased email claim against a non-archived row at
        ``gym_id`` whose ``employee_type`` is in ``allowed``. The single
        query behind both ``verify_roles`` and ``get_employee_id``.

        Returns:
            ``(employee_id, employee_type)`` for the matched row.

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if no
                matching non-archived row exists for the caller.
        """
        email = self._require_email(user_payload)

        resp = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id, employee_type")
            .eq("gym_id", str(gym_id))
            .eq("email", email)
            .in_("employee_type", [r.value for r in allowed])
            .is_("archived_at", "null")
            .maybe_single()
            .execute()
        )

        if not resp or not resp.data:
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
            UUID(resp.data["employee_id"]),
            EmployeeType(resp.data["employee_type"]),
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
        ``gym_employees`` row whose ``employee_type`` is in ``allowed``.

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
        allowed: frozenset[EmployeeType] = OWNER_ADMIN,
    ) -> UUID:
        """Resolve the caller's ``employee_id`` for a gym.

        Used to stamp the operator/witness on records a staff member
        captures (e.g. a waiver signature). Same email-based
        authorization as ``verify_roles`` — the caller must hold one of
        ``allowed`` roles (default owner/admin) on a non-archived row —
        but returns the ``employee_id`` instead of only asserting access.

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
        allowed: frozenset[EmployeeType] = OWNER_ADMIN,
    ) -> None:
        """Verify the caller holds one of ``allowed`` roles at ANY gym.

        The gym-AGNOSTIC staff gate, for endpoints that take no ``gym_id``
        (e.g. the shared image-upload proxy). Matches the caller's
        verified email against a non-archived ``gym_employees`` row at any
        gym whose ``employee_type`` is in ``allowed`` (default
        owner/admin).

        Raises:
            HTTPException: 401 if the token has no email claim, 403 if the
                caller holds no allowed role at any gym.
        """
        email = self._require_email(user_payload)

        resp = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("email", email)
            .in_("employee_type", [r.value for r in allowed])
            .is_("archived_at", "null")
            .limit(1)
            .execute()
        )

        if not resp or not resp.data:
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

    async def verify_can_view_member(
        self,
        member_id: UUID,
        user_payload: dict,
        staff_roles: frozenset[EmployeeType] = OWNER_ADMIN,
    ) -> None:
        """Verify the caller may view this member.

        Access is granted when the caller IS the member (their verified
        email matches the member row's ``email`` — a parent's account
        matches every member row bearing their email, covering the family
        case) OR the caller holds one of ``staff_roles`` (default
        owner/admin) at the member's gym.

        Raises:
            HTTPException: 404 if the member is not found, 401 if the token
                has no email claim, 403 if the caller is not authorized.
        """
        member = await (
            self._supabase.client.from_("members")
            .select("email, gym_id")
            .eq("member_id", str(member_id))
            .maybe_single()
            .execute()
        )

        if not member or not member.data:
            logger.error(
                "Member not found: member_id=%s",
                member_id,
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Member not found",
            ) from None

        caller_email = self._require_email(user_payload)
        member_email = (member.data.get("email") or "").lower()
        if member_email == caller_email:
            return

        await self.verify_roles(
            UUID(member.data["gym_id"]),
            user_payload,
            staff_roles,
        )

    async def _get_member_gym_id(self, member_id: UUID) -> UUID:
        """Resolve a member's gym_id.

        Raises:
            HTTPException: 404 if the member is not found.
        """
        member = await (
            self._supabase.client.from_("members")
            .select("gym_id")
            .eq("member_id", str(member_id))
            .maybe_single()
            .execute()
        )

        if not member or not member.data:
            logger.error(
                "Member not found: member_id=%s",
                member_id,
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Member not found",
            ) from None

        return UUID(member.data["gym_id"])

    async def verify_gym_employee_for_member(
        self,
        member_id: UUID,
        user_payload: dict,
        staff_roles: frozenset[EmployeeType] = OWNER_ADMIN,
    ) -> None:
        """Verify the caller holds one of ``staff_roles`` at the member's
        gym.

        Staff-only: unlike ``verify_can_view_member`` this does NOT grant
        the member themselves access. Resolves the member's gym then runs
        ``verify_roles`` with ``staff_roles`` (default owner/admin). Gates
        staff-managed billing writes — e.g. authorizing / de-authorizing a
        payer — that a member must not self-serve.

        Raises:
            HTTPException: 404 if the member is not found, 401 if the token
                has no email claim, 403 if the caller holds no allowed role
                at the member's gym.
        """
        gym_id = await self._get_member_gym_id(member_id)
        await self.verify_roles(gym_id, user_payload, staff_roles)

    async def get_employee_id_for_member(
        self,
        member_id: UUID,
        user_payload: dict,
        allowed: frozenset[EmployeeType] = OWNER_ADMIN,
    ) -> UUID:
        """Resolve the caller's ``employee_id`` for a member's gym.

        The member-scoped variant of ``get_employee_id``. Both authorizes
        (the caller must hold one of ``allowed`` roles, default
        owner/admin, at the member's gym) and returns the ``employee_id``
        — used to stamp the operator/witness when staff capture a signature
        in a member-scoped flow (the authorize-payer link flow).

        Raises:
            HTTPException: 404 if the member is not found, 401 if the token
                has no email claim, 403 if the caller holds no allowed role
                at the member's gym.
        """
        gym_id = await self._get_member_gym_id(member_id)
        return await self.get_employee_id(gym_id, user_payload, allowed)
