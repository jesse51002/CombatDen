"""Pytest fixtures for live integration tests.

Authenticates against the local Supabase instance as the seeded gym owner
and provides an authorised httpx.Client + the owner's gym_id so per-domain
test modules can hit the live FastAPI backend at http://localhost:8000.

Prerequisites:
- ``uvicorn src.main:app --reload`` is already running on port 8000.
- Local Supabase stack (``supabase start``) is up on port 54321.
- The seed data includes owner1@test.com / abcd1234 mapped to the one seeded gym.
"""

import os

import httpx
import pytest
from dotenv import dotenv_values

from src.core.config import settings
from tests.seed_constants import (
    SEEDED_GYM_ID,
    SEEDED_OWNER_EMAIL,
    SEEDED_OWNER_PASSWORD,
)

_ENV_PATH = os.path.join(os.path.dirname(__file__), "..", "..", ".env")

# Fallback key used by the CRM flutter project (new-format publishable key).
_FALLBACK_ANON_KEY = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

# Env-overridable so a worktree/branch can run the suite against its OWN
# backend instance on a free port (:8000 usually serves another checkout's
# backend / main's server).
BACKEND_BASE_URL = os.environ.get("BACKEND_BASE_URL", "http://localhost:8000")


def _load_env() -> tuple[str, str]:
    """Return (supabase_url, anon_key) from the .env file."""
    env = dotenv_values(_ENV_PATH)
    url = env.get("SUPABASE_URL", "http://127.0.0.1:54321")
    key = env.get("SUPABASE_ANON_KEY", "")
    return url, key


def _sign_in(
    supabase_url: str, anon_key: str, email: str, password: str
) -> str:
    """POST to Supabase Auth and return the access_token.

    Args:
        supabase_url: Base URL of the local Supabase instance.
        anon_key: Supabase anon key to use as the ``apikey`` header.
        email: The account to sign in as.
        password: That account's password.

    Returns:
        JWT access token string.

    Raises:
        RuntimeError: If the sign-in request fails.
    """
    url = f"{supabase_url}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": anon_key,
        "Content-Type": "application/json",
    }
    body = {"email": email, "password": password}
    response = httpx.post(url, json=body, headers=headers, timeout=30.0)
    response.raise_for_status()
    data = response.json()
    token = data.get("access_token", "")
    if not token:
        raise RuntimeError(
            f"Sign-in succeeded but no access_token in response: {data}"
        )
    return token


def sign_in_as(email: str, password: str) -> str:
    """Sign in as any seeded user and return the JWT access token.

    The reusable password-grant helper the role-scoped integration tests use
    to obtain a token for each seeded role. Tries the anon key from .env
    first; falls back to the CRM publishable key if the primary is rejected.
    """
    supabase_url, primary_key = _load_env()
    try:
        return _sign_in(supabase_url, primary_key, email, password)
    except Exception:
        return _sign_in(supabase_url, _FALLBACK_ANON_KEY, email, password)


def authed_client(token: str) -> httpx.Client:
    """An ``httpx.Client`` pointed at the live backend, bearing ``token``."""
    return httpx.Client(
        base_url=BACKEND_BASE_URL,
        headers={"Authorization": f"Bearer {token}"},
        timeout=30.0,
    )


class AdminAuthClient:
    """Minimal Supabase Auth Admin API client (service-role), over httpx.

    Mirrors the seed's ``create_user(..., email_confirm=True)``: the FastApi
    backend venv has no ``supabase`` package, so this calls the admin REST API
    directly. Only creation is exposed — test teardown removes the auth user
    by id via ``cleanup.delete_auth_user`` (direct DB, cascades identities).
    """

    def __init__(self, supabase_url: str, service_role_key: str) -> None:
        self._base = f"{supabase_url}/auth/v1/admin"
        self._headers = {
            "apikey": service_role_key,
            "Authorization": f"Bearer {service_role_key}",
            "Content-Type": "application/json",
        }

    def create_user(
        self, email: str, password: str, *, email_confirm: bool = True
    ) -> str:
        """Create a verified auth user; return its ``auth.users`` id."""
        resp = httpx.post(
            f"{self._base}/users",
            headers=self._headers,
            json={
                "email": email,
                "password": password,
                "email_confirm": email_confirm,
            },
            timeout=30.0,
        )
        resp.raise_for_status()
        return resp.json()["id"]


@pytest.fixture(scope="session")
def admin_client() -> AdminAuthClient:
    """A service-role auth-admin client for provisioning verified logins.

    Lets a test provision a verified login for an employee email so
    ``invite_status`` flips ``pending`` → ``active``.
    """
    return AdminAuthClient(
        settings.supabase_url, settings.supabase_service_role_key
    )


@pytest.fixture(scope="session")
def auth_token() -> str:
    """Sign in as the seeded gym owner and return the JWT access token."""
    return sign_in_as(SEEDED_OWNER_EMAIL, SEEDED_OWNER_PASSWORD)


@pytest.fixture(scope="session")
def api(auth_token: str) -> httpx.Client:
    """Authorised httpx.Client pointed at the live backend.

    Session-scoped so the TCP connection is reused across all integration
    tests in a run.
    """
    client = authed_client(auth_token)
    yield client
    client.close()


@pytest.fixture(scope="session")
def gym_id() -> str:
    """The one seeded gym id (hardcoded; see tests/seed_constants.py).

    There is exactly one seeded gym, so integration tests always target it
    rather than discovering it via the API.
    """
    return SEEDED_GYM_ID
