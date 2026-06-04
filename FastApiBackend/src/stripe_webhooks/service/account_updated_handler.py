"""Handler for Stripe ``account.updated`` events.

Connect fires ``account.updated`` whenever a connected Express
account's state changes — onboarding progress, disabled_reason
flips, payouts being enabled, etc.  The handler projects the
Stripe Account dict into the canonical
``gyms.stripe_onboarding_status`` value and writes it to ``gyms``.

Dedupe via ``stripe_webhook_events`` is handled by the outer
dispatcher — this handler participates in the same transaction.
"""

import logging
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.shared.sql_loader import load_sql
from src.stripe_webhooks import SQL_DIR

logger = logging.getLogger(__name__)

EVENT_TYPE = "account.updated"

GYM_STATUS_PENDING = "pending"
GYM_STATUS_COMPLETE = "complete"
GYM_STATUS_DISABLED = "disabled"


@dataclass(frozen=True)
class _GymStripeAccountSnapshot:
    """Flat projection of the Stripe Account fields we care about."""

    status: str
    details_submitted: bool
    charges_enabled: bool
    payouts_enabled: bool
    disabled_reason: str | None
    requirements_currently_due: list[str]


class AccountUpdatedHandler:
    """Sync a connected account's onboarding status into ``gyms``."""

    async def handle(
        self,
        session: AsyncSession,
        event: dict[str, Any],
        gym_id: UUID,
    ) -> None:
        account = event["data"]["object"]
        if not isinstance(account, dict):
            raise ValueError(
                "account.updated event payload is not a dict",
            )

        snapshot = self._map_account_to_snapshot(account)

        sql = load_sql(SQL_DIR / "gyms_set_onboarding_status.sql")
        await session.execute(
            text(sql),
            {
                "gym_id": str(gym_id),
                "status": snapshot.status,
            },
        )

        logger.info(
            "account.updated: gym_id=%s stripe_account_id=%s status=%s "
            "details_submitted=%s charges_enabled=%s payouts_enabled=%s "
            "disabled_reason=%s",
            gym_id,
            account.get("id"),
            snapshot.status,
            snapshot.details_submitted,
            snapshot.charges_enabled,
            snapshot.payouts_enabled,
            snapshot.disabled_reason,
        )

    def _map_account_to_snapshot(self, account: Any) -> _GymStripeAccountSnapshot:
        """Project a Stripe Account object or dict into a DB-status snapshot.

        Mapping rules:
            - ``requirements.disabled_reason`` set -> ``disabled``
            - ``details_submitted && charges_enabled && payouts_enabled``
              -> ``complete``
            - otherwise -> ``pending``
        """
        details_submitted = bool(self._get(account, "details_submitted", False))
        charges_enabled = bool(self._get(account, "charges_enabled", False))
        payouts_enabled = bool(self._get(account, "payouts_enabled", False))

        requirements = self._get(account, "requirements", None) or {}
        disabled_reason = self._get(requirements, "disabled_reason", None)
        currently_due = self._get(requirements, "currently_due", None) or []
        if not isinstance(currently_due, list):
            currently_due = list(currently_due)

        if disabled_reason:
            status = GYM_STATUS_DISABLED
        elif details_submitted and charges_enabled and payouts_enabled:
            status = GYM_STATUS_COMPLETE
        else:
            status = GYM_STATUS_PENDING

        return _GymStripeAccountSnapshot(
            status=status,
            details_submitted=details_submitted,
            charges_enabled=charges_enabled,
            payouts_enabled=payouts_enabled,
            disabled_reason=disabled_reason,
            requirements_currently_due=list(currently_due),
        )

    def _get(self, obj: Any, key: str, default: Any) -> Any:
        """Attribute-or-key lookup so we work on objects and plain dicts alike."""
        if obj is None:
            return default
        if isinstance(obj, dict):
            return obj.get(key, default)
        return getattr(obj, key, default)
