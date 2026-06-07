"""Canonical Stripe Account -> gyms.stripe_onboarding_status mapping.

Shared by the status refresh endpoint and the ``account.updated``
webhook handler so both derive the same DB value from the same
Stripe state. Keeping this in one place prevents drift between paths.

The DB ``stripe_onboarding_status`` enum allows ``not_started``,
``pending``, ``complete``, and ``disabled``. A Stripe account whose
``requirements.disabled_reason`` is set maps to ``disabled``; the
reason string itself is surfaced in the onboarding API response.
"""

from typing import Any

from schema.gym import StripeOnboardingStatus

import src.shared.db_schema_path  # noqa: F401
from src.gyms.schema.gyms_schema import GymStripeAccountSnapshot


def map_account_to_snapshot(account: Any) -> GymStripeAccountSnapshot:
    """Project a Stripe Account into a DB-status snapshot.

    Accepts either a ``stripe.Account`` (from the REST SDK, the
    status-refresh path) or a plain ``dict`` (the shape delivered by
    the ``account.updated`` webhook via ``event['data']['object']``).
    The Stripe object is normalized to a plain nested dict at the
    boundary with ``.to_dict()`` so a single ``dict.get()`` code path
    serves both callers.

    Mapping rules (precedence, aligned with the DB enum):
        - ``requirements.disabled_reason`` set -> ``disabled``
        - ``details_submitted && charges_enabled && payouts_enabled``
          -> ``complete``
        - otherwise -> ``pending``
    """
    data = account if isinstance(account, dict) else account.to_dict()

    details_submitted = bool(data.get("details_submitted", False))
    charges_enabled = bool(data.get("charges_enabled", False))
    payouts_enabled = bool(data.get("payouts_enabled", False))

    requirements = data.get("requirements") or {}
    disabled_reason = requirements.get("disabled_reason")
    currently_due = requirements.get("currently_due") or []
    if not isinstance(currently_due, list):
        currently_due = list(currently_due)

    if disabled_reason:
        status = StripeOnboardingStatus.disabled
    elif details_submitted and charges_enabled and payouts_enabled:
        status = StripeOnboardingStatus.complete
    else:
        status = StripeOnboardingStatus.pending

    return GymStripeAccountSnapshot(
        status=status,
        details_submitted=details_submitted,
        charges_enabled=charges_enabled,
        payouts_enabled=payouts_enabled,
        disabled_reason=disabled_reason,
        requirements_currently_due=list(currently_due),
    )
