"""Suppression checks and the signed unsubscribe token.

The token is a signed statement of "this address, at this gym", not an id:
an unsubscribe link must work from a mail client with no session, and a
guessable/enumerable link would let anyone unsubscribe anyone. HMAC over the
address means the link carries its own authorization.
"""

import base64
import hashlib
import hmac
import logging
from uuid import UUID

from sqlalchemy import text

from src.emails import SQL_DIR
from src.emails.emails_registry import EmailCategory
from src.shared.database import DirectDatabasePool
from src.shared.sql_loader import load_sql

import src.shared.db_schema_path  # noqa: F401  # isort: skip
from schema.email import EmailSuppressionScope  # isort: skip

logger = logging.getLogger(__name__)

# Separates the two signed fields inside the token body. Neither an email
# address nor a UUID may contain it, so the split is unambiguous.
TOKEN_FIELD_SEPARATOR = "|"
# Separates the token body from its signature.
TOKEN_PART_SEPARATOR = "."
# Truncated HMAC-SHA256, hex. 32 hex chars = 128 bits — far beyond forgeable
# for an unsubscribe link, and short enough to survive a mail client's line
# wrapping intact.
SIGNATURE_LENGTH = 32


class EmailsSuppression:
    """The pre-send suppression gate plus unsubscribe token mint/verify."""

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        unsubscribe_secret: str,
    ) -> None:
        self._db_pool = db_pool
        self._secret = unsubscribe_secret.encode()

    async def is_suppressed(
        self,
        email: str,
        gym_id: UUID,
        category: EmailCategory,
    ) -> bool:
        """Is this address opted out of mail of this category, at this gym?

        A ``marketing`` category is blocked by a ``marketing`` OR an ``all``
        suppression; a ``transactional`` one only by ``all`` — opting out of
        a pitch must never cost someone the link that gets them into the
        product. A global (``gym_id IS NULL``) suppression is a dead or
        hostile mailbox and blocks every gym.
        """
        sql = load_sql(SQL_DIR / "suppression_check.sql")
        params = {
            "email": email,
            "gym_id": str(gym_id),
            "include_marketing": category is EmailCategory.marketing,
        }
        async with self._db_pool.session() as session:
            result = await session.execute(text(sql), params)
            row = result.mappings().fetchone()
        return row is not None

    async def suppress(
        self,
        email: str,
        gym_id: UUID | None,
        scope: EmailSuppressionScope,
        reason: str,
    ) -> None:
        """Record a suppression. Idempotent — a repeat click is a no-op.

        ``gym_id=None`` is GLOBAL, for a hard bounce: a dead mailbox is dead
        for every gym.
        """
        sql = load_sql(SQL_DIR / "suppression_insert.sql")
        await self._db_pool.execute_with_retry(
            sql,
            {
                "gym_id": str(gym_id) if gym_id else None,
                "email": email,
                "scope": str(scope),
                "reason": reason,
            },
        )

    def mint_token(self, email: str, gym_id: UUID) -> str:
        """Mint the signed token embedded in a marketing email's link."""
        body = self._encode(
            f"{email.lower()}{TOKEN_FIELD_SEPARATOR}{gym_id}"
        )
        return f"{body}{TOKEN_PART_SEPARATOR}{self._sign(body)}"

    def verify_token(self, token: str) -> tuple[str, UUID] | None:
        """Verify a token and recover ``(email, gym_id)``.

        Returns None on ANY failure — bad signature, malformed body, bad
        UUID. The caller answers all of them identically, so a probe learns
        nothing from the response.
        """
        body, _, signature = token.partition(TOKEN_PART_SEPARATOR)
        if not body or not signature:
            return None
        if not hmac.compare_digest(signature, self._sign(body)):
            return None
        try:
            decoded = self._decode(body)
            email, separator, raw_gym = decoded.partition(
                TOKEN_FIELD_SEPARATOR
            )
            if not separator or not email:
                return None
            return email, UUID(raw_gym)
        except (ValueError, UnicodeDecodeError):
            return None

    def _sign(self, body: str) -> str:
        """The truncated hex HMAC-SHA256 of an encoded token body."""
        digest = hmac.new(
            self._secret, body.encode(), hashlib.sha256
        ).hexdigest()
        return digest[:SIGNATURE_LENGTH]

    @staticmethod
    def _encode(value: str) -> str:
        """URL-safe, unpadded base64 — a token rides in a query string."""
        raw = base64.urlsafe_b64encode(value.encode()).decode()
        return raw.rstrip("=")

    @staticmethod
    def _decode(value: str) -> str:
        """Reverse ``_encode``, restoring the stripped base64 padding."""
        padding = "=" * (-len(value) % 4)
        return base64.urlsafe_b64decode(value + padding).decode()
