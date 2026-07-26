"""Resolve a payload to an address + gym branding, at send time.

**This file is why the emails domain stays cycle-free.** Every other domain
may enqueue email, so the emails domain must import NOTHING from any other
domain's services — it owns its own two small reads over ``gym_employees``
and ``members`` instead of calling ``EmployeesService`` / members services
that will themselves want to enqueue email. Two tiny SELECTs are the cheap
price of a one-way dependency graph.

Resolution happens at SEND time, never at claim time: a row claimed today and
delivered by tomorrow's retry sweep goes to the address the gym has NOW.
"""

import logging
from typing import Any
from uuid import UUID

from sqlalchemy import text

from src.emails import SQL_DIR
from src.emails.schema.emails_schema import ResolvedRecipient
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailKind  # isort: skip

logger = logging.getLogger(__name__)


class EmailsRecipients:
    """Payload → ``ResolvedRecipient``, or None when there is no address."""

    # Which SQL file resolves which kind's subject. A kind whose subject is
    # neither an employee nor a member adds its own entry here.
    _SUBJECT_QUERIES: dict[EmailKind, str] = {
        EmailKind.staff_onboarding: "recipient_employee.sql",
        EmailKind.member_app_invite: "recipient_member.sql",
    }

    # Payload field naming the subject row, per kind.
    _SUBJECT_FIELDS: dict[EmailKind, str] = {
        EmailKind.staff_onboarding: "employee_id",
        EmailKind.member_app_invite: "member_id",
    }

    def __init__(self, db_pool: DirectDatabasePool) -> None:
        self._db_pool = db_pool

    @classmethod
    def subject_id(cls, payload: dict[str, Any]) -> UUID | None:
        """The id of the person this payload's email is about.

        Also the value written to ``email_log.subject_id``, which is what
        makes the per-person resend cap an indexed count rather than a
        JSONB dig.
        """
        kind = EmailKind(payload["kind"])
        field = cls._SUBJECT_FIELDS.get(kind)
        if field is None:
            return None
        raw = payload.get(field)
        return UUID(str(raw)) if raw else None

    async def resolve(
        self,
        payload: dict[str, Any],
    ) -> ResolvedRecipient | None:
        """Resolve a payload's recipient.

        Returns:
            The address + gym branding, or None when the subject has no
            usable address (no email on file, or an archived employee). None
            is a legitimate outcome, not an error: engagement-only members
            genuinely have no email.
        """
        kind = EmailKind(payload["kind"])
        query = self._SUBJECT_QUERIES.get(kind)
        subject = self.subject_id(payload)
        if query is None or subject is None:
            return None

        sql = load_sql(SQL_DIR / query)
        params = {
            "subject_id": str(subject),
            "gym_id": str(payload["gym_id"]),
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()

        if not row:
            return None
        return ResolvedRecipient(**dict(row))
