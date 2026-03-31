"""Generate a Supabase-compatible JWT for local development/testing."""

import argparse
import json
from datetime import datetime, timedelta, timezone

import jwt

SUPABASE_DEV_JWT_SECRET = (
    "super-secret-jwt-token-with-at-least-32-characters-long"
)

DEFAULT_EXPIRY_DAYS = 30


def generate_token(user_id: str, expiry_days: int) -> str:
    """Generate a signed JWT with Supabase-compatible claims."""
    now = datetime.now(timezone.utc)
    payload = {
        "sub": user_id,
        "aud": "authenticated",
        "role": "authenticated",
        "iss": "supabase",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(days=expiry_days)).timestamp()),
    }
    token = jwt.encode(payload, SUPABASE_DEV_JWT_SECRET, algorithm="HS256")
    return token


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate a Supabase dev JWT token."
    )
    parser.add_argument(
        "--user-id", required=True, help="UUID for the sub claim"
    )
    parser.add_argument(
        "--expiry",
        type=int,
        default=DEFAULT_EXPIRY_DAYS,
        help=f"Days until expiry (default: {DEFAULT_EXPIRY_DAYS})",
    )
    args = parser.parse_args()

    token = generate_token(args.user_id, args.expiry)

    decoded = jwt.decode(
        token,
        SUPABASE_DEV_JWT_SECRET,
        algorithms=["HS256"],
        audience="authenticated",
    )
    print("Token:")
    print(token)
    print("\nDecoded payload:")
    print(json.dumps(decoded, indent=2))


if __name__ == "__main__":
    main()
