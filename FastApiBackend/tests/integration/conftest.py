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

from tests.seed_constants import (
    SEEDED_GYM_ID,
    SEEDED_OWNER_EMAIL,
    SEEDED_OWNER_PASSWORD,
)

_ENV_PATH = os.path.join(os.path.dirname(__file__), "..", "..", ".env")

_OWNER_EMAIL = SEEDED_OWNER_EMAIL
_OWNER_PASSWORD = SEEDED_OWNER_PASSWORD

# Fallback key used by the CRM flutter project (new-format publishable key).
_FALLBACK_ANON_KEY = "sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH"

BACKEND_BASE_URL = "http://localhost:8000"


def _load_env() -> tuple[str, str]:
    """Return (supabase_url, anon_key) from the .env file."""
    env = dotenv_values(_ENV_PATH)
    url = env.get("SUPABASE_URL", "http://127.0.0.1:54321")
    key = env.get("SUPABASE_ANON_KEY", "")
    return url, key


def _sign_in(supabase_url: str, anon_key: str) -> str:
    """POST to Supabase Auth and return the access_token.

    Args:
        supabase_url: Base URL of the local Supabase instance.
        anon_key: Supabase anon key to use as the ``apikey`` header.

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
    body = {"email": _OWNER_EMAIL, "password": _OWNER_PASSWORD}
    response = httpx.post(url, json=body, headers=headers, timeout=30.0)
    response.raise_for_status()
    data = response.json()
    token = data.get("access_token", "")
    if not token:
        raise RuntimeError(
            f"Sign-in succeeded but no access_token in response: {data}"
        )
    return token


@pytest.fixture(scope="session")
def auth_token() -> str:
    """Sign in as the seeded gym owner and return the JWT access token.

    Tries the anon key from .env first; falls back to the CRM publishable key
    if the primary key is rejected.
    """
    supabase_url, primary_key = _load_env()

    try:
        token = _sign_in(supabase_url, primary_key)
        return token
    except Exception:
        pass

    # Primary key failed — try the fallback.
    token = _sign_in(supabase_url, _FALLBACK_ANON_KEY)
    return token


@pytest.fixture(scope="session")
def api(auth_token: str) -> httpx.Client:
    """Authorised httpx.Client pointed at the live backend.

    Session-scoped so the TCP connection is reused across all integration
    tests in a run.
    """
    client = httpx.Client(
        base_url=BACKEND_BASE_URL,
        headers={"Authorization": f"Bearer {auth_token}"},
        timeout=30.0,
    )
    yield client
    client.close()


@pytest.fixture(scope="session")
def gym_id() -> str:
    """The one seeded gym id (hardcoded; see tests/seed_constants.py).

    There is exactly one seeded gym, so integration tests always target it
    rather than discovering it via the API.
    """
    return SEEDED_GYM_ID
