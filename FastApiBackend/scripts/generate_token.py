"""Fetch a Supabase JWT token for local development/testing (e.g. Postman)."""

import argparse
import json

import httpx

import sys
sys.path.append(".")
from src.core.config import settings

DEFAULT_SUPABASE_URL = "http://127.0.0.1:54321"


def fetch_token(email: str, password: str) -> dict:
    """Sign in via Supabase Auth and return the session data.

    Args:
        email: User email address.
        password: User password.

    Returns:
        Dict containing access_token, refresh_token, user, etc.
    """
    url = f"{settings.supabase_url}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": settings.supabase_anon_key,
        "Content-Type": "application/json",
    }
    body = {"email": email, "password": password}

    response = httpx.post(url, json=body, headers=headers, timeout=30.0)
    response.raise_for_status()
    return response.json()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch a Supabase JWT token for local dev/Postman.",
    )
    parser.add_argument(
        "--email", required=True, help="User email address",
    )
    parser.add_argument(
        "--password", required=True, help="User password",
    )
    args = parser.parse_args()

    session = fetch_token(args.email, args.password)

    print("Access Token:")
    print(session["access_token"])
    print("\nToken Type:", session.get("token_type"))
    print("Expires In:", session.get("expires_in"), "seconds")
    print("\nFull Response:")
    print(json.dumps(session, indent=2))


if __name__ == "__main__":
    main()
