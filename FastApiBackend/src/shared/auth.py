"""Authentication and authorization for Supabase JWT tokens."""

import logging
from uuid import UUID

import jwt
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from postgrest.exceptions import APIError

from src.core.config import settings
from src.shared.database import SupabaseClient

logger = logging.getLogger(__name__)

security = HTTPBearer()


class Auth:
    """Handles Supabase JWT authentication and gym ownership verification."""

    def __init__(self, supabase: SupabaseClient) -> None:
        self._jwt_secret = settings.supabase_jwt_secret
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
            payload = jwt.decode(
                credentials.credentials,
                self._jwt_secret,
                algorithms=["HS256"],
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

    async def verify_can_view_member(
        self,
        crm_user_id: UUID,
        user_payload: dict,
    ) -> None:
        """Verify the authenticated user can view this member.

        Access is granted if the user is the member themselves
        (linked account) or the owner of the member's gym.

        Args:
            crm_user_id: The member's CRM user ID.
            user_payload: Decoded JWT payload from get_current_user.

        Raises:
            HTTPException: 404 if member not found,
                403 if user is not authorized.
        """
        auth_user_id = user_payload["sub"]

        try:
            member = await (
                self._supabase.client.from_("user_gym_profiles")
                .select("user_id, gym_id")
                .eq("crm_user_id", str(crm_user_id))
                .single()
                .execute()
            )
        except APIError:
            logger.error(
                "Member not found: crm_user_id=%s",
                crm_user_id,
                exc_info=True,
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Member not found",
            ) from None

        if member.data["user_id"] == auth_user_id:
            return

        try:
            gym = await (
                self._supabase.client.from_("gyms")
                .select("owner_id")
                .eq("gym_id", member.data["gym_id"])
                .single()
                .execute()
            )
        except APIError:
            logger.error(
                "Gym not found: gym_id=%s",
                member.data["gym_id"],
                exc_info=True,
            )
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Gym not found",
            ) from None

        if gym.data["owner_id"] == auth_user_id:
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
