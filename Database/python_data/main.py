"""Seed orchestrator.

Single `make seed` that creates a gym's full demo dataset. Stripe-backed rows
go through the FastAPI backend so every plan / price / discount / member /
membership ends up with a real test-mode Stripe ID; the rest is direct-DB.

Flow:
  1. Pre-flight: assert the backend is reachable.
  2. Bootstrap gyms + owner auth users + employees (direct DB). Each gym is
     stamped with the shared Stripe Connect test account.
  3. Insert global rank_presets.
  4. Per gym, signed in as the gym owner:
       a. Clone the rank ladder into gym_ranks (direct DB).
       b. Plans + prices via the backend (real Stripe products/prices).
       c. Discounts (regular-only presets) via the backend (coupons computed
          at sync, not on the preset). The catalog randomizes %/$ and
          lifetime (a few billing cycles / a day-week-month span / forever).
       d. Build the per-member billing lifecycle (incl. a random
          0-DISCOUNTS_PER_MEMBERSHIP_MAX discount set per membership), then
          create every member concurrently via the backend (POST /members shell
          -> contact UPDATE -> PUT /card creates the Stripe customer). The
          backend member_id threads into all engagement seeding below.
       e. Historical (closed) memberships inserted direct-DB BEFORE live ones
          (keeps the recurring chronological/no-active triggers happy).
       f. Live memberships via the backend (real Stripe subscriptions),
          concurrent BY FAMILY: each paying-parent family runs its sequence
          (start parent -> link + start children -> freeze -> apply discounts)
          on one worker, several families at once.
       g. A couple of overdue members via Stripe test clocks (direct Stripe).
       i. Engagement (direct DB, keyed on the backend member_ids): classes
          (identity + append-only schedule versions), attendance,
          class_signups (past + future reservations), rewards + redemptions,
          activities.
       j. Invoice + charge history (direct DB, synthetic Stripe IDs).
       k. gym_history rollup.

Requires the backend running (`make run` in FastApiBackend), a Stripe test
key, and Supabase password sign-in enabled. The user runs migrations + seed
manually.
"""

from __future__ import annotations

import random
import time

import progress
from api_client import assert_backend_reachable, login_gym_owner
from api_creation import discounts as api_discounts
from api_creation import members as api_members
from api_creation import memberships as api_memberships
from api_creation import overdue_members as api_overdue
from api_creation import plans as api_plans
from bootstrap import activities as bs_activities
from bootstrap import classes as bs_classes
from bootstrap import gyms as bs_gyms
from bootstrap import history as bs_history
from bootstrap import ranks as bs_ranks
from bootstrap import rewards as bs_rewards
from bootstrap import waivers as bs_waivers
from config import get_supabase_client
from constants import DEFAULT_PASSWORD, DISCOUNTS_PER_GYM, PLANS_PER_GYM, SEED
from faker import Faker
from generators import invoices as gen_invoices
from generators import members as members_generator
from generators import memberships as gen_memberships
from schema.gym_rank import GymType

# Cycle through the three presets across seeded gyms so all paths get exercised.
_GYM_TYPE_CYCLE = [GymType.bjj, GymType.mma, GymType.generic]


def seed() -> None:
    # Pin the PRNGs so every run is deterministic — the api_creation upsert
    # helpers rely on stable emails/plan names to find existing rows on re-run.
    random.seed(SEED)
    Faker.seed(SEED)
    members_generator.fake.unique.clear()
    api_overdue.fake.unique.clear()

    seed_start = time.perf_counter()
    assert_backend_reachable()
    client = get_supabase_client()

    # Phase 1: bootstrap gyms (with stripe_account_id) + auth users + employees.
    bundles = bs_gyms.create_all(client)

    # Phase 2: rank presets (global, once).
    progress.log("\nCreating rank presets...")
    bs_ranks.create_presets(client)

    # Phase 3: per-gym data.
    for i, bundle in enumerate(bundles):
        gym_id = bundle.gym_id
        gym_type = _GYM_TYPE_CYCLE[i % len(_GYM_TYPE_CYCLE)]
        progress.log(f"\n=== {bundle.gym_name} ({gym_id}) — {gym_type.value} ===")
        gym_start = time.perf_counter()

        with login_gym_owner(bundle.owner_email, DEFAULT_PASSWORD) as api:
            # Ranks (clone from preset, direct DB).
            progress.log("Creating gym ranks...")
            ranks = bs_ranks.create_gym_ranks(client, gym_id, gym_type)
            progress.log(f"  {len(ranks)} ranks")

            # Payer-auth authorized-payer waiver (undeletable, direct DB).
            progress.log("Creating payer-auth waiver...")
            bs_waivers.create(client, gym_id)

            # Plans + prices (real Stripe products + prices).
            progress.log("Creating plans...")
            plan_records = api_plans.create_all(
                api, client, gym_id, PLANS_PER_GYM
            )
            progress.log(f"  {len(plan_records)} plans")

            # Discounts (regular presets; coupons computed at sync). The catalog
            # randomizes %/$ and lifetime (cycle / span / forever); memberships
            # draw a random subset of it below.
            progress.log("Creating discounts...")
            regular_discounts = api_discounts.create_regular(
                api, client, gym_id, DISCOUNTS_PER_GYM
            )
            progress.log(f"  {len(regular_discounts)} discounts")

            # Build the per-member billing lifecycle. Each live membership is
            # pre-assigned a random 0-DISCOUNTS_PER_MEMBERSHIP_MAX set of the
            # gym's discounts (applied when the membership is started below).
            progress.log("Building member plans...")
            member_plans = members_generator.build_plans(
                gym_handle=f"gym-{gym_id}",
                ranks=ranks,
                plans=plan_records,
                discounts=regular_discounts,
            )

            # Create every member via the backend (real Stripe customers).
            # Concurrent across members — creation takes no per-family lock.
            progress.log(f"Creating {len(member_plans)} members via API...")
            result = api_members.create_all(api, client, gym_id, member_plans)

            # Historical (closed) memberships BEFORE any live ones — the
            # recurring chronological/no-active triggers require history to be
            # in first. Only on a run that created new members (a no-reset
            # re-run would duplicate rows and trip the triggers).
            history_rows: list = []
            if result.had_any_new:
                progress.log("Inserting historical memberships...")
                history_rows = gen_memberships.create_history(client, gym_id, member_plans)
                progress.log(f"  {len(history_rows)} historical rows")

            # Live memberships, concurrent BY FAMILY: each paying-parent family
            # runs its sequence on one worker (link each child -> start the whole
            # family in ONE request, each membership carrying its random discounts
            # applied before the first charge -> freeze), and several families run
            # at once. Families have disjoint per-parent lock keys, so concurrency
            # never contends the billing lock.
            progress.log("Starting live memberships + discounts via API...")
            current_records = api_memberships.create_memberships(
                api, client, gym_id, member_plans
            )
            progress.log(f"  {len(current_records)} live memberships")

            # A couple of overdue members via Stripe test clocks.
            if result.had_any_new:
                progress.log("Creating overdue members via Stripe test clocks...")
                api_overdue.create_overdue(client, gym_id, plan_records)

            # Liability waiver, attached to every plan AFTER the membership
            # phase (the start gate would 422 the seed's own starts if plans
            # required an unsigned waiver earlier). Existing members show it
            # unsigned; any NEW start demos the gate + wizard sign step.
            progress.log("Creating liability waiver + attaching to plans...")
            liability_waiver_id = bs_waivers.create_liability(client, gym_id)
            api_plans.attach_waiver(
                api, gym_id, plan_records, liability_waiver_id
            )

        # --- direct-DB engagement (no JWT needed), keyed on backend member_ids ---
        members = [members_generator.to_member_create(gym_id, p) for p in member_plans]

        # Membership coverage for attendance attribution + invoice history:
        # historical (inserted) rows plus synthetic rows for the live
        # memberships (their item_ids are the real backend item_ids; the
        # windows are plausible). Attendance is attributed to whichever
        # membership covers each occurrence.
        pseudo_current = gen_memberships.pseudo_rows_for_current(
            gym_id, current_records, member_plans
        )
        membership_rows = history_rows + pseudo_current

        progress.log("Creating classes...")
        classes, schedules, instance_exc, range_exc = bs_classes.create(
            client, gym_id, bundle.gym.timezone, bundle.gym_name, bundle.all_employees
        )

        progress.log("Creating rewards...")
        gym_rewards = bs_rewards.create(client, gym_id)

        progress.log("Creating class attendance...")
        eligible_classes, attendance = bs_classes.create_attendance(
            client,
            gym_id,
            bundle.gym.timezone,
            bundle.gym_name,
            classes,
            schedules,
            members,
            membership_rows,
            instance_exc,
            range_exc,
        )

        progress.log("Creating class sign-ups...")
        bs_classes.create_signups(
            client,
            gym_id,
            bundle.gym.timezone,
            bundle.gym_name,
            classes,
            eligible_classes,
            schedules,
            members,
            attendance,
            instance_exc,
            range_exc,
        )

        progress.log("Creating reward redemptions...")
        bs_rewards.create_redemptions(client, gym_id, members, gym_rewards)

        progress.log("Creating activities...")
        bs_activities.create(client, gym_id, members, ranks)

        # Invoice + charge history (direct DB, synthetic Stripe IDs). Guarded
        # like the membership history above so re-runs don't duplicate.
        if result.had_any_new:
            progress.log("Creating invoices and charges...")
            inv, li, ch = gen_invoices.generate(
                gym_id, membership_rows, plan_records
            )
            if inv:
                client.table("member_invoices").insert(
                    [r.to_insert_dict() for r in inv]
                ).execute()
            if li:
                client.table("member_invoice_line_items").insert(
                    [r.to_insert_dict() for r in li]
                ).execute()
            if ch:
                client.table("member_charges").insert(
                    [r.to_insert_dict() for r in ch]
                ).execute()
            progress.log(f"  {len(inv)} invoices, {len(li)} line items, {len(ch)} charges")

        progress.log("Creating gym history...")
        bs_history.create(client, gym_id, member_count=len(members))

        gym_elapsed = time.perf_counter() - gym_start
        progress.log(f"=== {bundle.gym_name} done in {gym_elapsed:.1f}s ===")

    total_elapsed = time.perf_counter() - seed_start
    progress.log(f"\nSeeding complete! (total {total_elapsed:.1f}s)")


if __name__ == "__main__":
    seed()
