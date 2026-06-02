"""Unit tests for the Postgres URL → asyncpg-driver normalization (pure, no DB).

Guards that a raw Supabase / standard connection string pasted into .env or
.env.prod is coerced onto the async driver the engine needs.
"""

from __future__ import annotations

from src.shared.database import to_asyncpg_url


def test_plain_postgresql_gets_asyncpg() -> None:
    assert (
        to_asyncpg_url("postgresql://u:p@db.x.supabase.co:5432/postgres")
        == "postgresql+asyncpg://u:p@db.x.supabase.co:5432/postgres"
    )


def test_postgres_scheme_gets_asyncpg() -> None:
    assert (
        to_asyncpg_url("postgres://u:p@h:5432/db")
        == "postgresql+asyncpg://u:p@h:5432/db"
    )


def test_already_asyncpg_is_unchanged() -> None:
    url = "postgresql+asyncpg://u:p@h:5432/db"
    assert to_asyncpg_url(url) == url


def test_other_driver_is_unchanged() -> None:
    # An explicitly-named driver is respected, not overridden.
    url = "postgresql+psycopg://u:p@h:5432/db"
    assert to_asyncpg_url(url) == url
