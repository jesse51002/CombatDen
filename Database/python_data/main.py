"""Seed orchestrator.

Flow:
  1. Pre-flight: assert backend is reachable.
  2. bootstrap: direct-DB creation of gyms, auth users, employees.
  3. Sign in as each gym owner (Supabase password auth) → JWTs.
  4. api_creation: plans, prices, discounts, members, current memberships
     — all via the FastAPI backend, so every Stripe-backed row has real IDs.
  5. bootstrap: classes, rewards (no endpoints, direct DB).
  6. generators: historical memberships, invoices, activities, reward
     redemptions, class logs, gym history — all direct-DB synthetic data.

Everything API-backed comes first so the real crm_user_id / plan_id /
price_id / discount_id values are available to downstream generators.
"""

from __future__ import annotations

import random

from api_client import assert_backend_reachable, login_gym_owner
from api_creation import (
    discounts as api_discounts,
)
from api_creation import (
    members as api_members,
)
from api_creation import (
    memberships as api_memberships,
)
from api_creation import (
    overdue_members as api_overdue,
)
from api_creation import (
    plans as api_plans,
)
from bootstrap import activities as bs_activities
from bootstrap import classes as bs_classes
from bootstrap import gyms as bs_gyms
from bootstrap import history as bs_history
from bootstrap import rewards as bs_rewards
from config import get_supabase_client
from constants import DEFAULT_PASSWORD, DISCOUNTS_PER_GYM, PLANS_PER_GYM, SEED
from faker import Faker
from generators import invoices, memberships
from generators.profiles import build_plans


def seed() -> None:
    # Pin the PRNGs so every run picks the same names, emails, plans,
    # discounts, and journey choices. The idempotency helpers in
    # api_creation/upsert.py rely on these stable keys to find existing
    # rows on re-run instead of POSTing to Stripe again.
    random.seed(SEED)
    Faker.seed(SEED)
    # `fake.unique` memoizes previously-handed-out values at module scope.
    # Clear it once at the start of each seed() call so the seeded RNG can
    # reliably regenerate the same emails/phones when seed() runs twice
    # inside a single Python process (e.g. from a test runner).
    from generators import profiles as _profiles_mod

    _profiles_mod.fake.unique.clear()

    assert_backend_reachable()
    client = get_supabase_client()

    # Phase 1: Bootstrap gyms, auth users, employees (direct DB).
    bundles = bs_gyms.create_all(client)

    # Phase 2: Per-gym API creations + remaining bootstrap + synthetic history.
    for bundle in bundles:
        print(f"\n=== {bundle.gym_name} ({bundle.gym_id}) ===")

        # Sign in as the gym owner; this gym's API calls run through `api`.
        with login_gym_owner(bundle.owner_email, DEFAULT_PASSWORD) as api:
            # Plans + prices (real Stripe products + prices).
            print("Creating plans...")
            plan_records = api_plans.create_all(api, client, bundle.gym_id, PLANS_PER_GYM)
            print(f"  {len(plan_records)} plans created")

            # Discounts (real Stripe coupons).
            print("Creating discounts...")
            regular_discounts = api_discounts.create_regular(
                api, client, bundle.gym_id, DISCOUNTS_PER_GYM
            )
            linked_discounts = api_discounts.create_linked(
                api, client, bundle.gym_id, plan_records
            )
            print(f"  {len(regular_discounts)} regular, {len(linked_discounts)} linked")

            # Classes + schedules (direct DB — no endpoint).
            # Skip on re-runs: if any class row already exists for this gym
            # we reuse what's there. The return values (parents, schedules)
            # are only consumed by the direct-DB generators below, which
            # are themselves gated on `had_any_new`.
            print("Creating classes...")
            class_plans_shim = _plan_records_to_shim(bundle.gym_id, plan_records)
            if _gym_has_rows(client, "gym_classes", bundle.gym_id):
                print("  already present, skipping")
                parents, schedules = [], []
            else:
                parents, schedules = bs_classes.create(
                    client,
                    bundle.gym_id,
                    bundle.gym_name,
                    bundle.all_employees,
                    class_plans_shim,
                )

            # Rewards (direct DB — no endpoint).
            print("Creating rewards...")
            if _gym_has_rows(client, "gym_rewards", bundle.gym_id):
                print("  already present, skipping")
                gym_rewards = []
            else:
                gym_rewards = bs_rewards.create(client, bundle.gym_id)

            # Build the in-memory profile plan for every member of this gym.
            print("Building profile plans...")
            linked_auth_ids = [u["id"] for u in bundle.linked_auth_users]
            profile_plans = build_plans(
                gym_handle=f"gym-{bundle.gym_id}",
                linked_auth_user_ids=linked_auth_ids,
                plans=plan_records,
                discounts=regular_discounts,
                linked_discounts=linked_discounts,
            )

            # Create every member via POST /members → real cus_*.
            print(f"Creating {len(profile_plans)} members via API...")
            members_result = api_members.create_all(api, client, bundle.gym_id, profile_plans)
            api_members.apply_links(client, profile_plans)

            # Insert historical (closed) membership rows BEFORE starting any
            # live ones. The `recurring_requires_no_active` trigger blocks
            # historical recurring inserts if a live recurring row already
            # exists for that user, so we get history in first. Only runs
            # when at least one member was freshly created — re-running
            # with existing data would duplicate history rows and crash on
            # the chronological/overlap triggers.
            history_rows: list = []
            if members_result.had_any_new:
                print("Inserting historical memberships...")
                history_rows = memberships.create_history(client, bundle.gym_id, profile_plans)
                print(f"  {len(history_rows)} historical rows")
            else:
                print("Skipping historical memberships (no new members)")

            # Start a live membership for every profile that has one.
            # Must run BEFORE apply_freezes — starting a membership on a
            # frozen account is rejected by the backend.
            print("Starting live memberships via API...")
            current_records = api_memberships.create_current(
                api, client, bundle.gym_id, profile_plans
            )
            print(f"  {len(current_records)} live memberships started")

            # Apply account-level freeze windows now that memberships exist.
            api_members.apply_freezes(client, profile_plans)

            # A couple of overdue members per gym (direct Stripe + DB).
            # Idempotent guard: skip on re-runs where overdue seed rows
            # already exist for this gym.
            if members_result.had_any_new:
                print("Creating overdue members via Stripe test clocks...")
                api_overdue.create_overdue(client, bundle.gym_id, plan_records)

        # --- direct-DB synthetic history (no JWT needed) ---

        # Skip the entire direct-DB block on pure re-runs. These generators
        # insert rows with auto-generated PKs, so running them a second
        # time would duplicate every invoice, charge, activity, class log,
        # and gym_history rollup for the gym. When any member was freshly
        # created we run the whole block as before.
        if not members_result.had_any_new:
            print("Skipping direct-DB history (no new members)")
            continue

        # Pseudo rows for current memberships so invoices have a past.
        pseudo_current = memberships.pseudo_rows_for_current(bundle.gym_id, current_records)
        all_membership_rows = history_rows + pseudo_current

        # Invoices + line items + charges + applied discounts (direct DB, fake IDs).
        print("Creating invoices and charges...")
        inv_rows, li_rows, ch_rows, ad_rows = invoices.generate(
            bundle.gym_id,
            all_membership_rows,
            plan_records,
            regular_discounts,
            linked_discounts,
        )
        if inv_rows:
            client.table("user_gym_invoices").insert(
                [i.to_insert_dict() for i in inv_rows]
            ).execute()
        if li_rows:
            client.table("user_gym_invoice_line_items").insert(
                [li.to_insert_dict() for li in li_rows]
            ).execute()
        if ad_rows:
            client.table("user_gym_invoice_applied_discounts").insert(
                [ad.to_insert_dict() for ad in ad_rows]
            ).execute()
        if ch_rows:
            client.table("user_gym_charges").insert(
                [c.to_insert_dict() for c in ch_rows]
            ).execute()
        print(f"  {len(inv_rows)} invoices, {len(li_rows)} line items, {len(ch_rows)} charges")

        # User activities (direct DB).
        print("Creating activities...")
        profiles_for_db = _profiles_for_db(bundle.gym_id, profile_plans)
        bs_activities.create(client, bundle.gym_id, profiles_for_db)

        # Reward redemptions (direct DB).
        print("Creating reward redemptions...")
        bs_rewards.create_redemptions(client, bundle.gym_id, profiles_for_db, gym_rewards)

        # Class attendance logs (direct DB). We pass both real + historical
        # membership rows so every active window during the simulated past
        # gets logs.
        print("Creating class logs...")
        bs_classes.create_logs(
            client,
            bundle.gym_id,
            bundle.gym_name,
            schedules,
            profiles_for_db,
            all_membership_rows,
        )

        # Gym history rollup (direct DB).
        print("Creating gym history...")
        bs_history.create(client, bundle.gym_id, member_count=len(profile_plans))

    print("\nSeeding complete!")


def _gym_has_rows(client, table: str, gym_id) -> bool:
    """True if `table` has at least one row for this gym.

    Used to skip direct-DB bootstrap steps (classes, rewards) that were
    already populated by a previous seed run.
    """
    resp = client.table(table).select("gym_id").eq("gym_id", str(gym_id)).limit(1).execute()
    return bool(resp.data)


def _plan_records_to_shim(gym_id, plan_records):
    """Adapt PlanRecord to MembershipPlanCreate for generators that still need it.

    classes.generate() reads plan_type on each plan to decide whether a class
    is "short-term only". We only need enough of the shape for that check.
    """
    from schema.membership_plan import MembershipPlanCreate

    return [
        MembershipPlanCreate(
            plan_id=p.plan_id,
            gym_id=gym_id,
            plan_name=p.plan_name,
            plan_type=p.plan_type,
            class_count=p.class_count,
            duration_amount=p.duration_amount,
            duration_unit=p.duration_unit,
            is_public=True,
        )
        for p in plan_records
    ]


def _profiles_for_db(gym_id, profile_plans):
    """Build UserGymProfileCreate shims for generators that still expect them.

    activities, reward_redemptions, and classes.generate_logs all take
    UserGymProfileCreate. We shim just the fields they read: crm_user_id,
    gym_id, and (for classes) account_linked_to_id + freeze dates.
    """
    import uuid

    from schema.user_gym_profile import UserGymProfileCreate

    handle_to_crm: dict[str, uuid.UUID] = {
        p.local_handle: p.crm_user_id  # type: ignore[assignment]
        for p in profile_plans
        if p.crm_user_id is not None
    }
    shims = []
    for p in profile_plans:
        if p.crm_user_id is None:
            continue
        linked_crm = None
        if p.linked_primary_handle is not None:
            linked_crm = handle_to_crm.get(p.linked_primary_handle)
        shims.append(
            UserGymProfileCreate(
                crm_user_id=p.crm_user_id,
                gym_id=gym_id,
                first_name=p.demographics.first_name,
                last_name=p.demographics.last_name,
                email=p.demographics.email,
                phone=p.demographics.phone,
                account_linked_to_id=linked_crm,
                freeze_start_date=p.account_freeze_start,
                freeze_end_date=p.account_freeze_end,
            )
        )
    return shims


if __name__ == "__main__":
    seed()
