"""Authentication and authorization for Supabase JWT tokens."""

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


class Auth:
    """Handles Supabase JWT authentication and gym ownership verification."""

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

    async def verify_gym_employee(
        self,
        gym_id: UUID,
        user_payload: dict,
    ) -> None:
        """Verify the authenticated user is a STAFF PRINCIPAL of the gym —
        an owner or admin.

        TRAINERS ARE NOT PRINCIPALS: a ``gym_employees`` row with
        ``employee_type = 'trainer'`` is instructor DATA (a name/photo shown
        on classes), never a login. Trainers have no accounts at all, so
        every staff check — read or write — resolves to owner/admin; the
        type filter here makes that explicit rather than relying on trainer
        rows never carrying a ``user_id``.

        Raises:
            HTTPException: 403 if user is not an owner/admin of
                the gym.
        """
        auth_user_id = user_payload["sub"]

        employee = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .eq("gym_id", str(gym_id))
            .in_(
                "employee_type",
                [EmployeeType.owner.value, EmployeeType.admin.value],
            )
            .maybe_single()
            .execute()
        )

        if not employee or not employee.data:
            logger.warning(
                "Unauthorized gym access attempt: user=%s, gym_id=%s",
                auth_user_id,
                gym_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to access this gym",
            ) from None

    async def get_employee_id(
        self,
        gym_id: UUID,
        user_payload: dict,
    ) -> UUID:
        """Resolve the authenticated staff principal's ``employee_id`` for a gym.

        Used to stamp the operator/witness on records a staff member captures
        (e.g. a waiver signature). Same authorization as ``verify_gym_employee``
        — resolves to an owner/admin (trainers are not principals) — but returns
        the ``employee_id`` instead of only asserting membership.

        Raises:
            HTTPException: 403 if the user is not an owner/admin of the gym.
        """
        auth_user_id = user_payload["sub"]

        employee = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .eq("gym_id", str(gym_id))
            .in_(
                "employee_type",
                [EmployeeType.owner.value, EmployeeType.admin.value],
            )
            .maybe_single()
            .execute()
        )

        if not employee or not employee.data:
            logger.warning(
                "Unauthorized gym access attempt: user=%s, gym_id=%s",
                auth_user_id,
                gym_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized to access this gym",
            ) from None

        return UUID(employee.data["employee_id"])

    async def verify_staff_principal(
        self,
        user_payload: dict,
    ) -> None:
        """Verify the authenticated user is a STAFF PRINCIPAL (owner or
        admin) of AT LEAST ONE gym.

        The gym-agnostic staff gate, for endpoints that take no ``gym_id``
        (e.g. the shared image-upload proxy). Same owner/admin bar as
        ``verify_gym_employee`` — trainers are not principals — just without
        the per-gym scope.

        Raises:
            HTTPException: 403 if the user is not an owner/admin of any gym.
        """
        auth_user_id = user_payload["sub"]

        employee = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .in_(
                "employee_type",
                [EmployeeType.owner.value, EmployeeType.admin.value],
            )
            .limit(1)
            .execute()
        )

        if not employee or not employee.data:
            logger.warning(
                "Unauthorized staff-only action attempt: user=%s",
                auth_user_id,
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
        """Verify the authenticated user is an OWNER of the gym.

        Gates owner-only actions (Stripe Connect onboarding). Admins
        and trainers are rejected even though they may otherwise
        access the gym.

        Raises:
            HTTPException: 403 if the user is not an owner of the gym.
        """
        auth_user_id = user_payload["sub"]

        owner = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .eq("gym_id", str(gym_id))
            .eq("employee_type", EmployeeType.owner.value)
            .maybe_single()
            .execute()
        )

        if not owner or not owner.data:
            logger.warning(
                "Unauthorized gym-owner action attempt: user=%s, gym_id=%s",
                auth_user_id,
                gym_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized: gym owner only",
            ) from None

    async def verify_gym_admin_or_owner(
        self,
        gym_id: UUID,
        user_payload: dict,
    ) -> None:
        """Verify the authenticated user is an ADMIN or OWNER of the gym.

        Gates gym-config writes (classes / rewards / discounts / plans
        create / update / delete). Mirrors the DB's
        ``is_gym_admin_or_owner`` RLS function at the API layer. Enforces
        the same set as ``verify_gym_employee`` (trainers are not
        principals — no accounts); both names are kept so call sites
        document intent: this one marks a deliberate WRITE gate.

        Raises:
            HTTPException: 403 if the user is neither an admin nor an
                owner of the gym.
        """
        auth_user_id = user_payload["sub"]

        manager = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .eq("gym_id", str(gym_id))
            .in_(
                "employee_type",
                [EmployeeType.owner.value, EmployeeType.admin.value],
            )
            .maybe_single()
            .execute()
        )

        if not manager or not manager.data:
            logger.warning(
                "Unauthorized gym-admin/owner action attempt: "
                "user=%s, gym_id=%s",
                auth_user_id,
                gym_id,
            )
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Not authorized: gym admin or owner only",
            ) from None

    async def verify_can_view_member(
        self,
        member_id: UUID,
        user_payload: dict,
    ) -> None:
        """Verify the authenticated user can view this member.

        Access is granted if the user is the member themselves or a staff
        principal (owner/admin — trainers are not principals, see
        ``verify_gym_employee``) of the member's gym.

        Raises:
            HTTPException: 404 if member not found,
                403 if user is not authorized.
        """
        auth_user_id = user_payload["sub"]

        member = await (
            self._supabase.client.from_("members")
            .select("user_id, gym_id")
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

        if member.data.get("user_id") == auth_user_id:
            return

        employee = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .eq("gym_id", member.data["gym_id"])
            .in_(
                "employee_type",
                [EmployeeType.owner.value, EmployeeType.admin.value],
            )
            .maybe_single()
            .execute()
        )

        if employee and employee.data:
            return

        logger.warning(
            "Unauthorized member access attempt: user=%s, member_id=%s",
            auth_user_id,
            member_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to view this member",
        ) from None

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
    ) -> None:
        """Verify the authenticated user is a staff principal (owner/admin) of
        this member's gym.

        Staff-only: unlike ``verify_can_view_member`` this does NOT grant the
        member themselves access. Like every staff check it resolves to
        admin/owner — trainers are not principals (see ``verify_gym_employee``).
        Gates staff-managed billing writes — e.g. authorizing / de-authorizing a
        payer — that a member must not self-serve.

        Raises:
            HTTPException: 404 if the member is not found, 403 if the user is
                not a staff principal of the member's gym.
        """
        gym_id = await self._get_member_gym_id(member_id)
        await self.verify_gym_employee(gym_id, user_payload)

    async def get_employee_id_for_member(
        self,
        member_id: UUID,
        user_payload: dict,
    ) -> UUID:
        """Resolve the authenticated staff member's ``employee_id`` for a
        member's gym (the member-scoped variant of ``get_employee_id``).

        Both authorizes (403 if the user is not an owner/admin of the member's
        gym) and returns the ``employee_id`` — used to stamp the operator/witness
        when staff capture a signature in a member-scoped flow (the
        authorize-payer link flow).

        Raises:
            HTTPException: 404 if the member is not found, 403 if the user is
                not a staff principal of the member's gym.
        """
        gym_id = await self._get_member_gym_id(member_id)
        return await self.get_employee_id(gym_id, user_payload)
