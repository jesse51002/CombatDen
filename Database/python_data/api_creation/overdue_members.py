"""Create a couple of overdue members per gym using Stripe test clocks.

Why this exists separately from the normal profile flow: a Stripe customer
has to be created *under* a test clock (the binding is immutable), and our
backend members-create API always creates its own customer. So for these
members we bypass both the members API and the memberships API, talking to
Stripe directly (see ``stripe_direct``) and inserting DB rows via the
service-role client.

Target state for each overdue member:
  - Real Stripe customer attached to its own test clock.
  - Declining card set as the default PM (``pm_card_chargeDeclined``).
  - Real recurring subscription whose first invoice failed on that card.
  - ``member_memberships`` row with ``next_due_date`` backdated so the
    membership is surfaced as overdue in the CRM.

Webhook forwarding: keep ``stripe listen --forward-to
localhost:8000/api/v1/webhooks/stripe`` running while the seed executes so
the backend receives the ``invoice.payment_failed`` events triggered by the
declining card. Without it the Stripe state is correct but ``next_due_date``
won't refresh after ``mark_paid_cash`` settles the open invoice.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from api_creation.plans import PlanRecord
from api_creation.stripe_direct import (
    advance_clock,
    attach_declining_payment_method,
    attach_working_payment_method,
    create_customer_under_clock,
    create_recurring_subscription,
    create_test_clock,
)
from constants import STRIPE_TEST_ACCOUNT_ID
from faker import Faker
from supabase import Client

OVERDUE_MEMBERS_PER_GYM = 2

fake = Faker()


def _random_phone() -> str:
    return f"+12025550{fake.random_int(min=100, max=999)}"


def create_overdue(
    client: Client,
    gym_id: uuid.UUID,
    plans: list[PlanRecord],
) -> list[uuid.UUID]:
    """Create ``OVERDUE_MEMBERS_PER_GYM`` overdue members for this gym.

    Returns the list of crm_user_ids that were freshly created. If recurring
    plans aren't available for this gym we skip silently.
    """
    recurring_plans = [p for p in plans if p.plan_type == "recurring"]
    if not recurring_plans:
        return []

    # Freeze each clock far enough in the past that advancing to "now" crosses
    # at least one renewal boundary for a monthly plan.
    frozen_at = datetime.now(UTC) - timedelta(days=40)
    advance_to = datetime.now(UTC)

    created: list[uuid.UUID] = []
    for i in range(OVERDUE_MEMBERS_PER_GYM):
        plan = recurring_plans[i % len(recurring_plans)]
        first_name = fake.first_name()
        last_name = fake.last_name()
        email = fake.unique.email()

        clock_id = create_test_clock(STRIPE_TEST_ACCOUNT_ID, frozen_at)

        customer_id = create_customer_under_clock(
            STRIPE_TEST_ACCOUNT_ID,
            clock_id=clock_id,
            name=f"{first_name} {last_name}",
            email=email,
            phone=_random_phone(),
            metadata={"gym_id": str(gym_id), "seed_overdue": "true"},
        )
        # Attach a working card first so the subscription's initial invoice
        # succeeds. We'll swap to the declining card before advancing the
        # clock so the renewal charge fails.
        pm_id = attach_working_payment_method(STRIPE_TEST_ACCOUNT_ID, customer_id)

        # Insert the CRM profile row directly — the row has to exist before
        # we can reference it from member_memberships, and we already have
        # the real Stripe customer we want to store.
        profile_insert = (
            client.table("user_gym_profiles")
            .insert(
                {
                    "gym_id": str(gym_id),
                    "first_name": first_name,
                    "last_name": last_name,
                    "email": email,
                    "phone": _random_phone(),
                    "address": fake.address().replace("\n", ", "),
                    "emergency_contact_name": fake.name(),
                    "emergency_contact_phone": _random_phone(),
                    "emergency_contact_email": fake.email(),
                    "stripe_customer_id": customer_id,
                    "stripe_payment_method_id": pm_id,
                    "card_brand": "visa",
                    "card_last_four": "4242",
                    "card_exp_month": 12,
                    "card_exp_year": datetime.now(UTC).year + 2,
                    "payment_type": "card",
                }
            )
            .execute()
        )
        crm_user_id = uuid.UUID(profile_insert.data[0]["crm_user_id"])

        sub_id, sub_item_id, period_end_ts = create_recurring_subscription(
            STRIPE_TEST_ACCOUNT_ID,
            stripe_customer_id=customer_id,
            stripe_price_id=plan.stripe_price_id,
            metadata={
                "crm_user_id": str(crm_user_id),
                "gym_id": str(gym_id),
            },
        )

        # Stamp the sub ID on the profile so the mark_paid_cash path can find
        # the subscription.
        client.table("user_gym_profiles").update(
            {"stripe_sub_id_month": sub_id}
        ).eq("crm_user_id", str(crm_user_id)).execute()

        # Insert the membership row. next_due_date is set to the Stripe
        # current_period_end; we'll overwrite it to a past date after
        # advancing the clock so the CRM flags it as overdue.
        start_date = frozen_at.date()
        client.table("member_memberships").insert(
            {
                "crm_user_id": str(crm_user_id),
                "gym_id": str(gym_id),
                "plan_id": str(plan.plan_id),
                "price_id": str(plan.price_id),
                "start_date": start_date.isoformat(),
                "last_paid_date": start_date.isoformat(),
                "next_due_date": datetime.fromtimestamp(period_end_ts, tz=UTC)
                .date()
                .isoformat(),
                "stripe_item_id": sub_item_id,
                "prorate": True,
                "total_price": plan.base_cost,
            }
        ).execute()

        # Swap the default PM to the declining card BEFORE advancing, so the
        # renewal charge fails while the initial invoice already settled.
        declining_pm_id = attach_declining_payment_method(
            STRIPE_TEST_ACCOUNT_ID, customer_id
        )
        client.table("user_gym_profiles").update(
            {
                "stripe_payment_method_id": declining_pm_id,
                "card_last_four": "0002",
            }
        ).eq("crm_user_id", str(crm_user_id)).execute()

        # Advance the clock to "now" — Stripe fires the renewal invoice,
        # charges the declining card, and the invoice stays ``open``.
        advance_clock(STRIPE_TEST_ACCOUNT_ID, clock_id, advance_to)

        # Backdate next_due_date so the membership shows as overdue
        # regardless of whether webhooks landed.
        client.table("member_memberships").update(
            {"next_due_date": (advance_to.date() - timedelta(days=5)).isoformat()}
        ).eq("stripe_item_id", sub_item_id).execute()

        created.append(crm_user_id)
        print(f"  overdue member created: {email} ({crm_user_id})")

    return created
