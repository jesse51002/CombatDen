"""Data access over ``email_log`` — the audit trail AND the retry queue."""

import json
import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.emails import SQL_DIR
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind, EmailStatus  # isort: skip

logger = logging.getLogger(__name__)


class EmailsLog:
    """Reads and writes for ``email_log``.

    ``claim`` is the one method that runs inside the CALLER's transaction
    (it takes their ``AsyncSession`` and never commits): the claim must live
    or die with the operation that triggered the email. Every other method
    is a standalone post-commit lifecycle write and opens its own session.
    """

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    async def claim(
        self,
        session: AsyncSession,
        payload: dict[str, Any],
        key: str,
        subject_id: UUID | None,
        initial_status: EmailStatus,
    ) -> UUID | None:
        """Claim one send inside the caller's OPEN transaction.

        Args:
            session: The caller's session. Not committed here — the caller
                owns the transaction, which is what makes a rolled-back
                operation un-send its email.
            payload: The validated payload as a JSON-able dict (IDs only).
            key: The idempotency key, e.g. ``staff_onboarding:<id>:0``.
            subject_id: The person the email is about, for the resend cap.
            initial_status: ``pending`` normally, ``held`` when the kind is
                not enabled.

        Returns:
            The new ``email_id``, or None when this key was already claimed.
        """
        sql = load_sql(SQL_DIR / "email_log_claim.sql")
        params = {
            "gym_id": str(payload["gym_id"]),
            "kind": str(payload["kind"]),
            "subject_id": str(subject_id) if subject_id else None,
            "idempotency_key": key,
            "status": str(initial_status),
            "payload": json.dumps(payload),
        }
        result = await session.execute(text(sql), params)
        row = result.mappings().fetchone()
        return UUID(str(row["email_id"])) if row else None

    async def load(self, email_id: UUID) -> dict[str, Any] | None:
        """Read one row, or None when it does not exist."""
        sql = load_sql(SQL_DIR / "email_log_load.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql), {"email_id": str(email_id)}
            )
            row = result.mappings().fetchone()
        return dict(row) if row else None

    async def mark_sent(
        self,
        email_id: UUID,
        provider_message_id: str | None,
        recipient: str,
    ) -> None:
        """Move the row to the terminal ``sent`` state."""
        sql = load_sql(SQL_DIR / "email_log_mark_sent.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {
                "email_id": str(email_id),
                "provider_message_id": provider_message_id,
                "recipient": recipient,
            },
        )

    async def mark_failed(self, email_id: UUID, error: str) -> None:
        """Record a retryable failure and bump the attempt counter."""
        sql = load_sql(SQL_DIR / "email_log_mark_failed.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {"email_id": str(email_id), "last_error": error},
        )

    async def mark_terminal(
        self,
        email_id: UUID,
        status: EmailStatus,
        recipient: str | None = None,
        error: str | None = None,
    ) -> None:
        """Close the row out with a terminal-by-policy status.

        Used for ``suppressed`` — a no-address subject or an opted-out
        address. Never pass ``sent`` here: that path must set ``sent_at``
        (``mark_sent``), or the ``sent_matches_status`` check rejects it.
        """
        sql = load_sql(SQL_DIR / "email_log_mark_terminal.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {
                "email_id": str(email_id),
                "status": str(status),
                "recipient": recipient,
                "last_error": error,
            },
        )

    async def pending_for_retry(
        self,
        limit: int,
        max_attempts: int,
    ) -> list[dict[str, Any]]:
        """The retry sweep's work list: unfinished rows, oldest first."""
        sql = load_sql(SQL_DIR / "email_log_pending_retry.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {"limit": limit, "max_attempts": max_attempts},
            )
            rows = result.mappings().fetchall()
        return [dict(row) for row in rows]

    async def count_total_for_subject(
        self,
        subject_id: UUID,
        kind: EmailKind,
    ) -> int:
        """How many rows of this kind have EVER existed for this person.

        The resend SEQUENCE, not the cap. It must never reset: it is what
        makes a deliberate resend a new idempotency key instead of a
        collision with the original claim. See the SQL file's header for why
        the windowed count cannot serve both roles.
        """
        sql = load_sql(SQL_DIR / "email_log_count_total.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "subject_id": str(subject_id),
                    "kind": str(kind),
                },
            )
            row = result.mappings().fetchone()
        return int(row["total_count"]) if row else 0

    async def count_recent_for_subject(
        self,
        subject_id: UUID,
        kind: EmailKind,
        within_seconds: int,
    ) -> int:
        """How many rows of this kind exist for this person in the window."""
        sql = load_sql(SQL_DIR / "email_log_count_recent.sql")
        async with self._db_pool.session() as session:
            result = await session.execute(
                text(sql),
                {
                    "subject_id": str(subject_id),
                    "kind": str(kind),
                    "within_seconds": within_seconds,
                },
            )
            row = result.mappings().fetchone()
        return int(row["recent_count"]) if row else 0
