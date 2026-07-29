"""Live integration proof of the member portal's gate.

The member surface is gated by ``Auth.verify_member_self``, whose whole job is
to answer three questions with one query: is the caller's verified email this
member's email, is the auth account CONFIRMED, and is the member in the PATH
gym. This exercises all three against the real backend + Supabase:

1. A member whose email backs a confirmed login reads their OWN data (identity
   list, profile, streak, history, schedule, rewards, redemptions, videos) and
   redeems a reward with their own points.
2. The SAME token gets 403 on ANOTHER member at the same gym.
3. The SAME token gets 403 on a member at a DIFFERENT gym — the hole the
   ``gym_id`` argument exists to close: without it, one email reaches a
   same-emailed member row at an unrelated gym.
4. The SAME token is 403 on a member of the caller's own gym reached through
   the WRONG path gym.
5. A member token is NOT staff — the CRM routes stay closed to it.
6. The family case works: a second member row bearing the SAME email is
   readable, because ``members.email`` has no uniqueness constraint by design.

Everything created (two members at the seeded gym, a reward, a redemption, the
auth login, plus a throwaway second gym and its one member) is removed on
teardown; no seeded row is touched.

Prereqs (same as the rest of tests/integration): the backend is running at
``BACKEND_BASE_URL`` on THIS branch's code, and the local Supabase stack is
seeded.
"""

from collections.abc import AsyncGenerator
from datetime import UTC, date, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text

from tests.helpers.db_writes import set_points_balance
from tests.integration.conftest import authed_client, sign_in_as
from tests.seed_constants import SEEDED_OWNER_PASSWORD

MEMBER_PORTAL = "/api/v1/member"


def _unique_email() -> str:
    """A fresh lowercase email that can't collide with the seed or a prior run."""
    return f"itest-portal-{uuid4().hex[:12]}@example.com"


def _portal(gym_id: str, member_id: str) -> str:
    return f"{MEMBER_PORTAL}/gyms/{gym_id}/members/{member_id}"


async def _set_member_email(db_pool, member_id: UUID, email: str) -> None:
    """Point a test member's row at a known address (identity is the email)."""
    async with db_pool.session() as session:
        await session.execute(
            text("UPDATE members SET email = :email WHERE member_id = :id"),
            {"email": email, "id": str(member_id)},
        )
        await session.commit()


@pytest.fixture
async def other_gym(db_pool) -> AsyncGenerator[dict]:
    """A throwaway second gym holding ONE member — the cross-gym axis.

    Created with a direct INSERT rather than ``POST /api/v1/gyms/`` on purpose:
    the API path provisions a Stripe Connect account, and nothing here needs
    one. Its own try/finally teardown deletes the member then the gym row.
    """
    async with db_pool.session() as session:
        gym_row = (
            await session.execute(
                text(
                    "INSERT INTO gyms (gym_name) VALUES (:name) "
                    "RETURNING gym_id"
                ),
                {"name": f"ZZ Portal Test Gym {uuid4().hex[:8]}"},
            )
        ).mappings().fetchone()
        await session.commit()
    gym_id = UUID(str(gym_row["gym_id"]))

    try:
        yield {"gym_id": gym_id, "db_pool": db_pool}
    finally:
        async with db_pool.session() as session:
            await session.execute(
                text("DELETE FROM members WHERE gym_id = :g"),
                {"g": str(gym_id)},
            )
            await session.execute(
                text("DELETE FROM gyms WHERE gym_id = :g"),
                {"g": str(gym_id)},
            )
            await session.commit()


async def _insert_member(db_pool, gym_id: UUID, email: str) -> UUID:
    """A bare members row (no Stripe customer — nothing here bills)."""
    async with db_pool.session() as session:
        row = (
            await session.execute(
                text(
                    "INSERT INTO members (gym_id, first_name, last_name, email) "
                    "VALUES (:g, 'ZZ', 'Portal', :email) RETURNING member_id"
                ),
                {"g": str(gym_id), "email": email},
            )
        ).mappings().fetchone()
        await session.commit()
    return UUID(str(row["member_id"]))


async def test_member_portal_serves_own_data_and_refuses_everyone_elses(
    gym_id: str,
    created,
    admin_client,
    db_pool,
    other_gym,
) -> None:
    """One verified member token: 200 on their own rows, 403 on every other."""
    email = _unique_email()

    # ── The caller: a member at the seeded gym whose email backs a
    #    CONFIRMED Supabase login.
    me = await created.member(UUID(gym_id), first_name="ZZ", last_name="Portal")
    await _set_member_email(db_pool, me.member_id, email)
    user_id = admin_client.create_user(
        email, SEEDED_OWNER_PASSWORD, email_confirm=True
    )
    created.track_auth_user(user_id)

    # ── A sibling: the family case — same email, second member row.
    sibling = await created.member(
        UUID(gym_id), first_name="ZZ", last_name="Sibling"
    )
    await _set_member_email(db_pool, sibling.member_id, email)

    # ── A stranger at the SAME gym (different email).
    stranger = await created.member(
        UUID(gym_id), first_name="ZZ", last_name="Stranger"
    )
    await _set_member_email(db_pool, stranger.member_id, _unique_email())

    # ── A member at a DIFFERENT gym carrying the caller's OWN email. The
    #    gym scope — not the email — is what must refuse this one.
    foreign_member_id = await _insert_member(
        db_pool, other_gym["gym_id"], email
    )

    client = authed_client(sign_in_as(email, SEEDED_OWNER_PASSWORD))
    try:
        # 1. The entry point resolves the caller's email to their member rows,
        #    across gyms — the family case, and the foreign gym's row too.
        resp = client.get(f"{MEMBER_PORTAL}/members")
        assert resp.status_code == 200, resp.text
        rows = resp.json()["members"]
        by_id = {r["member_id"]: r for r in rows}
        assert str(me.member_id) in by_id
        assert str(sibling.member_id) in by_id
        assert str(foreign_member_id) in by_id
        assert str(stranger.member_id) not in by_id
        assert by_id[str(me.member_id)]["gym_id"] == gym_id
        assert by_id[str(me.member_id)]["gym_name"]

        # 2. Their OWN data reads.
        resp = client.get(_portal(gym_id, str(me.member_id)))
        assert resp.status_code == 200, resp.text
        profile = resp.json()
        assert profile["member_id"] == str(me.member_id)
        assert "points_balance" in profile["retention"]

        assert client.get(
            f"{_portal(gym_id, str(me.member_id))}/streak"
        ).status_code == 200
        assert client.get(
            f"{_portal(gym_id, str(me.member_id))}/class-history"
        ).status_code == 200
        assert client.get(
            f"{_portal(gym_id, str(me.member_id))}/redemptions"
        ).status_code == 200
        assert client.get(
            f"{_portal(gym_id, str(me.member_id))}/rewards"
        ).status_code == 200
        assert client.get(
            f"{_portal(gym_id, str(me.member_id))}/videos"
        ).status_code == 200

        today = date.today()
        resp = client.get(
            f"{_portal(gym_id, str(me.member_id))}/classes",
            params={
                "start_date": today.isoformat(),
                "end_date": (today + timedelta(days=7)).isoformat(),
            },
        )
        assert resp.status_code == 200, resp.text
        assert "items" in resp.json()

        # 2b. The schedule window is span-bounded: a >2-month range is a 400
        # (an unbounded window would expand millions of occurrences in memory).
        wide = client.get(
            f"{_portal(gym_id, str(me.member_id))}/classes",
            params={
                "start_date": today.isoformat(),
                "end_date": (today + timedelta(days=200)).isoformat(),
            },
        )
        assert wide.status_code == 400, wide.text
        assert "too wide" in wide.json()["detail"].lower()

        # 3. The family case: the sibling row bearing the same email reads too.
        assert client.get(
            _portal(gym_id, str(sibling.member_id))
        ).status_code == 200

        # 4. ANOTHER member at the SAME gym — 403 (email mismatch).
        assert client.get(
            _portal(gym_id, str(stranger.member_id))
        ).status_code == 403
        assert client.get(
            f"{_portal(gym_id, str(stranger.member_id))}/streak"
        ).status_code == 403
        assert client.get(
            f"{_portal(gym_id, str(stranger.member_id))}/videos"
        ).status_code == 403

        # 5. A member at a DIFFERENT gym, reached through THIS gym's path —
        #    403 on the gym scope even though the email matches. This is the
        #    hole `gym_id` closes.
        assert client.get(
            _portal(gym_id, str(foreign_member_id))
        ).status_code == 403
        # ...and the caller's OWN member row through the WRONG gym is 403 too.
        assert client.get(
            _portal(str(other_gym["gym_id"]), str(me.member_id))
        ).status_code == 403

        # 6. An unknown member is 404, not 403 — nothing to be authorized for.
        assert client.get(_portal(gym_id, str(uuid4()))).status_code == 404

        # 7. A member token is NOT staff: the CRM surface stays closed.
        assert client.post(
            "/api/v1/members/list", json={"gym_id": gym_id, "view": "all"}
        ).status_code == 403
        assert client.get(
            "/api/v1/rewards/", params={"gym_id": gym_id}
        ).status_code == 403
        assert client.get(
            "/api/v1/classes/instances",
            params={
                "gym_id": gym_id,
                "start_date": today.isoformat(),
                "end_date": today.isoformat(),
            },
        ).status_code == 403
        assert client.get(
            f"/api/v1/members/{me.member_id}"
        ).status_code == 403
    finally:
        client.close()


async def test_member_redeems_their_own_reward_as_pending(
    gym_id: str,
    created,
    admin_client,
    db_pool,
) -> None:
    """A member spends their OWN points; the redemption lands PENDING.

    A member can never self-approve — ``auto_approve`` is hardwired false on
    the member route, so staff still hand the reward over.
    """
    email = _unique_email()
    me = await created.member(UUID(gym_id), first_name="ZZ", last_name="Redeemer")
    await _set_member_email(db_pool, me.member_id, email)
    await set_points_balance(db_pool, me.member_id, 500)
    user_id = admin_client.create_user(
        email, SEEDED_OWNER_PASSWORD, email_confirm=True
    )
    created.track_auth_user(user_id)

    reward = await created.reward(
        UUID(gym_id), title="ZZ Portal Reward", point_cost=100
    )

    client = authed_client(sign_in_as(email, SEEDED_OWNER_PASSWORD))
    try:
        resp = client.get(f"{_portal(gym_id, str(me.member_id))}/rewards")
        assert resp.status_code == 200, resp.text
        assert str(reward.reward_id) in {
            r["reward_id"] for r in resp.json()["items"]
        }

        resp = client.post(
            f"{_portal(gym_id, str(me.member_id))}/rewards/"
            f"{reward.reward_id}/redeem"
        )
        assert resp.status_code == 201, resp.text
        body = resp.json()
        created.track_redemption(UUID(body["redemption_id"]))
        assert body["status"] == "pending"
        assert body["points_balance_after"] == 400

        # It shows up in the member's own history.
        resp = client.get(f"{_portal(gym_id, str(me.member_id))}/redemptions")
        assert resp.status_code == 200, resp.text
        assert body["redemption_id"] in {
            r["redemption_id"] for r in resp.json()["items"]
        }
    finally:
        client.close()


async def test_member_reads_own_gym_theme_and_rank_progress_series(
    gym_id: str,
    created,
    admin_client,
    db_pool,
) -> None:
    """A member reads their OWN gym's theme (with ``theme_design_id``), is 403
    on ANOTHER gym's theme, and reads a rank-progress series that RESETS at a
    ``rank_changed`` and CAPS at ``classes_needed``.

    Runs entirely on a throwaway gym (its own rank, member, activities, and a
    known ``theme_design_id``) so nothing seeded is touched — the seeded gym is
    used only as the 'another gym' the member must be refused on. Its own
    try/finally removes exactly what it inserts (activities → member → rank →
    gym); the auth login is tracked on the ``created`` registry.
    """
    email = _unique_email()
    design_id = f"ZZ-design-{uuid4().hex[:8]}"
    # sub-rank-less rank on a default ('none') gym → classes_needed is the
    # full major threshold, so the cap is deterministic.
    classes_needed = 2

    async with db_pool.session() as session:
        my_gym = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO gyms (gym_name, theme_design_id) "
                            "VALUES (:name, :design) RETURNING gym_id"
                        ),
                        {
                            "name": f"ZZ Portal Theme Gym {uuid4().hex[:8]}",
                            "design": design_id,
                        },
                    )
                ).mappings().fetchone()["gym_id"]
            )
        )
        rank_id = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO gym_ranks (gym_id, "
                            "main_rank_num_order, name, classes_to_next_major) "
                            "VALUES (:g, 0, 'ZZ White', :n) RETURNING rank_id"
                        ),
                        {"g": str(my_gym), "n": classes_needed},
                    )
                ).mappings().fetchone()["rank_id"]
            )
        )
        member_id = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO members (gym_id, first_name, "
                            "last_name, email, current_rank_id) VALUES "
                            "(:g, 'ZZ', 'Ranked', :e, :r) RETURNING member_id"
                        ),
                        {"g": str(my_gym), "e": email, "r": str(rank_id)},
                    )
                ).mappings().fetchone()["member_id"]
            )
        )
        # 3 classes (the 3rd caps at classes_needed), a promotion (reset to 0),
        # then 2 more classes — increasing timestamps so the walk is ordered.
        base = datetime(2026, 6, 1, 12, 0, tzinfo=UTC)
        events = [
            ("class_attended", base),
            ("class_attended", base + timedelta(days=1)),
            ("class_attended", base + timedelta(days=2)),
            ("rank_changed", base + timedelta(days=3)),
            ("class_attended", base + timedelta(days=4)),
            ("class_attended", base + timedelta(days=5)),
        ]
        for activity_type, ts in events:
            await session.execute(
                text(
                    "INSERT INTO member_activities (member_id, gym_id, "
                    "activity_type, time) VALUES (:m, :g, "
                    "CAST(:t AS member_activity_type), :ts)"
                ),
                {
                    "m": str(member_id),
                    "g": str(my_gym),
                    "t": activity_type,
                    "ts": ts,
                },
            )
        await session.commit()

    user_id = admin_client.create_user(
        email, SEEDED_OWNER_PASSWORD, email_confirm=True
    )
    created.track_auth_user(user_id)

    client = authed_client(sign_in_as(email, SEEDED_OWNER_PASSWORD))
    try:
        # 1. Their OWN gym's theme reads — with the saved design id.
        resp = client.get(f"/api/v1/gyms/{my_gym}/showcase")
        assert resp.status_code == 200, resp.text
        assert resp.json()["theme_design_id"] == design_id

        # 2. ANOTHER gym's theme (the seeded gym) — 403, not an employee OR
        #    member of it.
        assert (
            client.get(f"/api/v1/gyms/{gym_id}/showcase").status_code == 403
        )

        # 3. Rank-progress resets at the rank_changed and caps at
        #    classes_needed: [1, 2, 2(cap), 0(reset), 1, 2].
        resp = client.get(
            f"{_portal(str(my_gym), str(member_id))}/rank-progress"
        )
        assert resp.status_code == 200, resp.text
        points = resp.json()["points"]
        assert [p["classes_into_rank"] for p in points] == [1, 2, 2, 0, 1, 2]
        assert {p["classes_needed"] for p in points} == {classes_needed}
    finally:
        client.close()
        async with db_pool.session() as session:
            await session.execute(
                text("DELETE FROM member_activities WHERE gym_id = :g"),
                {"g": str(my_gym)},
            )
            await session.execute(
                text("DELETE FROM members WHERE gym_id = :g"),
                {"g": str(my_gym)},
            )
            await session.execute(
                text("DELETE FROM gym_ranks WHERE gym_id = :g"),
                {"g": str(my_gym)},
            )
            await session.execute(
                text("DELETE FROM gyms WHERE gym_id = :g"),
                {"g": str(my_gym)},
            )
            await session.commit()
