"""Authentication and authorization for Supabase JWT tokens."""

import logging
from uuid import UUID

import jwt
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

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
        """Verify the authenticated user is an employee of the gym.

        Args:
            gym_id: The gym to check access for.
            user_payload: Decoded JWT payload from get_current_user.

        Raises:
            HTTPException: 403 if user is not an employee of
                the gym.
        """
        auth_user_id = user_payload["sub"]

        employee = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .eq("gym_id", str(gym_id))
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

    async def verify_can_view_member(
        self,
        crm_user_id: UUID,
        user_payload: dict,
    ) -> None:
        """Verify the authenticated user can view this member.

        Access is granted if the user is the member themselves
        (linked account) or an employee of the member's gym.

        Args:
            crm_user_id: The member's CRM user ID.
            user_payload: Decoded JWT payload from get_current_user.

        Raises:
            HTTPException: 404 if member not found,
                403 if user is not authorized.
        """
        auth_user_id = user_payload["sub"]

        member = await (
            self._supabase.client.from_("user_gym_profiles")
            .select("user_id, gym_id")
            .eq("crm_user_id", str(crm_user_id))
            .maybe_single()
            .execute()
        )

        if not member.data:
            logger.error(
                "Member not found: crm_user_id=%s",
                crm_user_id,
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Member not found",
            ) from None

        if member.data["user_id"] == auth_user_id:
            return

        employee = await (
            self._supabase.client.from_("gym_employees")
            .select("employee_id")
            .eq("user_id", auth_user_id)
            .eq("gym_id", member.data["gym_id"])
            .maybe_single()
            .execute()
        )

        if employee and employee.data:
            return

        logger.warning(
            "Unauthorized member access attempt: user=%s, crm_user_id=%s",
            auth_user_id,
            crm_user_id,
        )
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to view this member",
        ) from None
