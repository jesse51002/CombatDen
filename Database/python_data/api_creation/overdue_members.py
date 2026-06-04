"""Create a couple of overdue members per gym using Stripe test clocks.

Why this exists separately from the normal member flow: a Stripe customer has
to be created UNDER a test clock (the binding is immutable), and the backend's
card endpoint creates its own customer. So for these members we bypass both
the members API and the memberships API, talking to Stripe directly (see
stripe_direct) and inserting DB rows via the service-role client onto the
merged `members` table.

Target state for each overdue member:
  - Real Stripe customer attached to its own test clock.
  - Declining card set as the default PM (pm_card_chargeDeclined).
  - Real recurring subscription whose renewal invoice failed on that card.
  - member_memberships row with next_due_date backdated so the membership is
    surfaced as overdue in the CRM.

Keep `stripe listen --forward-to localhost:8000/api/v1/webhooks/stripe`
running while seeding so the backend receives the invoice.payment_failed
events the declining card triggers.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from api_creation.plans import PlanRecord
from api_creation.stripe_direct import (
    advance_clock,
    attach_working_payment_method,
    clear_default_payment_method,
    create_customer_under_clock,
    create_recurring_subscription,
    create_test_clock,
)
from constants import OVERDUE_MEMBERS_PER_GYM, STRIPE_TEST_ACCOUNT_ID
from faker import Faker
from supabase import Client

fake = Faker()


def _random_phone() -> str:
    return f"+1{fake.random_int(min=2000000000, max=9999999999)}"


def create_overdue(
    client: Client,
    gym_id: uuid.UUID,
    plans: list[PlanRecord],
) -> list[uuid.UUID]:
    """Create OVERDUE_MEMBERS_PER_GYM overdue members for this gym.

    Returns the freshly-created member_ids. Skips silently if no recurring
    plan is available.
    """
    recurring_plans = [p for p in plans if p.plan_type == "recurring"]
    if not recurring_plans:
        return []

    # Freeze each clock far enough in the past that advancing to "now" crosses
    # at least one monthly renewal boundary.
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
        # Working card first so the subscription's initial invoice succeeds;
        # we swap to the declining card before advancing the clock.
        pm_id = attach_working_payment_method(STRIPE_TEST_ACCOUNT_ID, customer_id)

        # Insert the member row directly (merged identity + billing) — it must
        # exist before we reference it from member_memberships, and we already
        # have the real Stripe customer to store on it.
        member_insert = (
            client.table("members")
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
        member_id = uuid.UUID(member_insert.data[0]["member_id"])

        sub_id, sub_item_id, period_end_ts = create_recurring_subscription(
            STRIPE_TEST_ACCOUNT_ID,
            stripe_customer_id=customer_id,
            stripe_price_id=plan.stripe_price_id,
            metadata={"member_id": str(member_id), "gym_id": str(gym_id)},
        )

        client.table("members").update({"stripe_sub_id_month": sub_id}).eq(
            "member_id", str(member_id)
        ).execute()

        start_date = frozen_at.date()
        client.table("member_memberships_unfiltered").insert(
            {
                "member_id": str(member_id),
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

        # Remove the card BEFORE advancing so the renewal fails. (The declining
        # test PM can't be used — pm_card_chargeDeclined is rejected at attach
        # time.) Detaching the working card leaves the renewal with no payment
        # method, so its invoice stays open and the subscription goes past_due.
        clear_default_payment_method(STRIPE_TEST_ACCOUNT_ID, customer_id, pm_id)
        client.table("members").update(
            {
                "stripe_payment_method_id": None,
                "card_brand": None,
                "card_last_four": None,
                "card_exp_month": None,
                "card_exp_year": None,
                "payment_type": None,
            }
        ).eq("member_id", str(member_id)).execute()

        # Advance the clock to "now" — Stripe fires the renewal invoice, the
        # declining card fails, the invoice stays open.
        advance_clock(STRIPE_TEST_ACCOUNT_ID, clock_id, advance_to)

        # Backdate next_due_date so the membership shows as overdue regardless
        # of whether webhooks landed.
        client.table("member_memberships_unfiltered").update(
            {"next_due_date": (advance_to.date() - timedelta(days=5)).isoformat()}
        ).eq("stripe_item_id", sub_item_id).execute()

        created.append(member_id)
        print(f"  overdue member created: {email} ({member_id})")

    return created
