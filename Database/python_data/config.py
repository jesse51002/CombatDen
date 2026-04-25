import os
from pathlib import Path

import httpx
from dotenv import load_dotenv
from supabase import Client, create_client

load_dotenv()

BACKEND_URL = os.environ.get("BACKEND_URL", "http://127.0.0.1:8000")


def get_supabase_client() -> Client:
    url = os.environ["SUPABASE_URL"]
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return create_client(url, key)


def get_supabase_url() -> str:
    return os.environ["SUPABASE_URL"]


def get_supabase_anon_key() -> str:
    return os.environ["SUPABASE_ANON_KEY"]


def fetch_access_token(email: str, password: str) -> str:
    """Sign in to Supabase with password and return the access_token JWT.

    Used by the seed script to obtain a gym-employee JWT for calling the
    FastAPI backend's authenticated endpoints.
    """
    url = f"{get_supabase_url()}/auth/v1/token?grant_type=password"
    headers = {
        "apikey": get_supabase_anon_key(),
        "Content-Type": "application/json",
    }
    resp = httpx.post(
        url,
        json={"email": email, "password": password},
        headers=headers,
        timeout=30.0,
    )
    resp.raise_for_status()
    return resp.json()["access_token"]
