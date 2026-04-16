"""Canonical Stripe Account -> gyms.stripe_onboarding_status mapping.

Shared by the status refresh endpoint and the ``account.updated``
webhook handler so both derive the same DB value from the same
Stripe state. Keeping this in one place prevents drift between the
two paths.
"""

from dataclasses import dataclass
from typing import Any

GYM_STATUS_PENDING = "pending"
GYM_STATUS_COMPLETE = "complete"
GYM_STATUS_DISABLED = "disabled"


@dataclass(frozen=True)
class GymStripeAccountSnapshot:
    """Flat projection of the Stripe Account fields we care about."""

    status: str
    details_submitted: bool
    charges_enabled: bool
    payouts_enabled: bool
    disabled_reason: str | None
    requirements_currently_due: list[str]


def map_account_to_snapshot(account: Any) -> GymStripeAccountSnapshot:
    """Project a Stripe Account object into a DB-status snapshot.

    Accepts either a ``stripe.Account`` (from the REST SDK) or a
    plain ``dict`` (the shape delivered by the ``account.updated``
    webhook via ``event['data']['object']``).

    Mapping rules:
        - ``requirements.disabled_reason`` set -> ``disabled``
        - ``details_submitted && charges_enabled && payouts_enabled``
          -> ``complete``
        - otherwise -> ``pending``
    """
    details_submitted = bool(_get(account, "details_submitted", False))
    charges_enabled = bool(_get(account, "charges_enabled", False))
    payouts_enabled = bool(_get(account, "payouts_enabled", False))

    requirements = _get(account, "requirements", None) or {}
    disabled_reason = _get(requirements, "disabled_reason", None)
    currently_due = _get(requirements, "currently_due", None) or []
    if not isinstance(currently_due, list):
        currently_due = list(currently_due)

    if disabled_reason:
        status = GYM_STATUS_DISABLED
    elif details_submitted and charges_enabled and payouts_enabled:
        status = GYM_STATUS_COMPLETE
    else:
        status = GYM_STATUS_PENDING

    return GymStripeAccountSnapshot(
        status=status,
        details_submitted=details_submitted,
        charges_enabled=charges_enabled,
        payouts_enabled=payouts_enabled,
        disabled_reason=disabled_reason,
        requirements_currently_due=list(currently_due),
    )


def _get(obj: Any, key: str, default: Any) -> Any:
    """Attribute-or-key lookup so we work on objects and dicts alike."""
    if obj is None:
        return default
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)
