"""The profile's ``latest_promotion`` block — the promotion animation's data.

The member app plays an old-belt → new-belt animation ONCE per new promotion,
driven by its own local watermark. That contract puts three demands on the
backend, and this file locks all three:

1. **Both belts arrive resolved.** The client holds no prior rank, so the row
   must carry the FROM leaf as well as the TO leaf. The rendered values come
   straight out of the activity's own snapshot — never a live join to
   ``gym_ranks``, whose image columns are user-writable.
2. **It degrades, it never fails.** A member who has never been promoted gets
   ``null``; a row written before the payload carried images gets null URLs and
   the client falls back to its themed belt. Nothing is backfilled.
3. **Only a REAL promotion surfaces.** ``member_activities`` logs every rank
   change — staff corrections, demotions and unassignments included — so the
   newest one is not automatically something to celebrate. The copy reads
   "You've been promoted", and congratulating a member on a demotion is worse
   than showing nothing, so anything that cannot be PROVEN to move the member
   up the ladder yields ``null``.

It rides the PROFILE read the celebration screen already makes, so there is no
extra round trip — and it is member-portal-private: ``MembersBillingDetailService``
(shared with the CRM member-detail card) is not touched.

Two halves. The projection/wire tests are hermetic (the DB pool and the
billing-detail service are doubles). The promotion FILTER lives in SQL — the
ladder order it compares against is a live ``gym_ranks`` read — so it is proven
against the real local Postgres, inside ONE session that is never committed.
The transaction rolls back on close, so no row survives and no seeded data is
touched.
"""

import json
from collections.abc import AsyncGenerator
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.main import app
from src.member_portal import SQL_DIR
from src.member_portal.schema.member_portal_schema import (
    MemberPortalProfile,
    MemberPortalPromotion,
)
from src.member_portal.service.member_portal_service import MemberPortalService
from src.members.schema.members_billing_schema import (
    BillingPersonalInfo,
    BillingRetention,
)
from src.ranks import SQL_DIR as RANKS_SQL_DIR
from src.shared.sql_loader import load_sql

PROMOTED_AT = datetime(2026, 7, 20, 18, 30, tzinfo=UTC)


def _detail(member_id: UUID, gym_id: UUID) -> MagicMock:
    """A ``MemberBillingDetailResponse`` double with real field values.

    Only the fields the portal projection reads are populated — the point of
    the projection is that nothing is re-derived here.
    """
    detail = MagicMock()
    detail.member_id = member_id
    detail.gym_id = gym_id
    detail.first_name = "Ada"
    detail.last_name = "Lovelace"
    detail.photo_url = None
    detail.personal_info = BillingPersonalInfo(email="ada@example.com")
    detail.retention = BillingRetention(
        last_class=None,
        class_streak_weeks=3,
        points_balance=250,
        videos_watched=7,
        current_week_attended_weekdays=[1, 3],
    )
    detail.rank = None
    detail.memberships = []
    detail.recently_redeemed_rewards = []
    detail.pending_redemptions = []
    return detail


def _service(row: dict | None, member_id: UUID, gym_id: UUID):
    """A ``MemberPortalService`` whose one activity read yields ``row``."""
    session = AsyncMock()
    session.__aenter__.return_value = session
    session.__aexit__.return_value = None
    result = MagicMock()
    result.mappings.return_value.fetchone.return_value = row
    session.execute = AsyncMock(return_value=result)

    pool = MagicMock()
    pool.session.return_value = session

    billing = MagicMock()
    billing.get_member_billing_detail = AsyncMock(
        return_value=_detail(member_id, gym_id)
    )
    return MemberPortalService(pool, billing), session


def _row(**overrides) -> dict:
    row = {
        "activity_id": uuid4(),
        "promoted_at": PROMOTED_AT,
        "old_rank_name": "White · 4 Stripes",
        "new_rank_name": "Blue",
        "old_image_url": "https://cdn.combatden.net/rank/white-4-stripes.png",
        "new_image_url": "https://cdn.combatden.net/rank/blue.png",
    }
    row.update(overrides)
    return row


# ── the service read ──────────────────────────────────────────────


async def test_profile_carries_the_latest_promotion_with_both_belts():
    """The profile read attaches the latest rank change, both belts resolved.

    ``activity_id`` is the watermark key the client compares against its
    stored value — an opaque immutable id, not a timestamp.
    """
    member_id, gym_id = uuid4(), uuid4()
    row = _row()
    service, session = _service(row, member_id, gym_id)

    profile = await service.get_profile(member_id)

    promotion = profile.latest_promotion
    assert promotion is not None
    assert promotion.activity_id == row["activity_id"]
    assert promotion.promoted_at == PROMOTED_AT
    assert promotion.old_rank_name == "White · 4 Stripes"
    assert promotion.new_rank_name == "Blue"
    assert promotion.old_image_url == row["old_image_url"]
    assert promotion.new_image_url == row["new_image_url"]
    # The rest of the profile is still the untouched CRM projection.
    assert profile.retention.points_balance == 250

    params = session.execute.await_args_list[0].args[1]
    assert params == {"member_id": str(member_id)}


async def test_latest_promotion_is_null_for_a_never_promoted_member():
    """No ``rank_changed`` row at all → ``None``, not an error.

    A member who has never been promoted is an ordinary state (a brand-new
    signup, or a gym with ranks switched off), and the client seeds its
    watermark silently on null rather than animating.
    """
    member_id, gym_id = uuid4(), uuid4()
    service, _session = _service(None, member_id, gym_id)

    profile = await service.get_profile(member_id)

    assert profile.latest_promotion is None
    assert await service.get_latest_promotion(member_id) is None


async def test_legacy_row_degrades_to_null_images():
    """A row written before the payload carried images still returns.

    ``->>`` yields NULL for an absent key, so the block arrives with its names
    intact and both URLs null — the client falls back to its themed belt.
    Nothing is backfilled to paper over it.
    """
    member_id, gym_id = uuid4(), uuid4()
    service, _session = _service(
        _row(old_image_url=None, new_image_url=None), member_id, gym_id
    )

    promotion = (await service.get_profile(member_id)).latest_promotion

    assert promotion is not None
    assert promotion.old_image_url is None
    assert promotion.new_image_url is None
    assert promotion.new_rank_name == "Blue"


async def test_first_assignment_has_no_old_belt():
    """The backfill / first assignment writes no "from" leaf.

    Both old fields stay null — an old belt is never fabricated, so the client
    renders a plain arrival rather than an animation out of nothing.
    """
    member_id, gym_id = uuid4(), uuid4()
    service, _session = _service(
        _row(old_rank_name=None, old_image_url=None), member_id, gym_id
    )

    promotion = (await service.get_profile(member_id)).latest_promotion

    assert promotion is not None
    assert promotion.old_rank_name is None
    assert promotion.old_image_url is None
    assert promotion.new_image_url is not None


def _promotion_sql_body() -> str:
    """The read's SQL with its comment lines stripped."""
    sql = (SQL_DIR / "member_portal_latest_promotion.sql").read_text()
    return "\n".join(
        line for line in sql.splitlines() if not line.lstrip().startswith("--")
    )


def test_latest_promotion_sql_renders_from_the_snapshot_not_a_live_join():
    """Everything the app RENDERS comes from ``activity_info``.

    A live lookup of the names or belt art would let a gym re-uploading its
    images rewrite what every past promotion looked like. ``gym_ranks`` is
    joined for exactly ONE thing — ``main_rank_num_order``, the ladder position
    that decides whether the change was a promotion, which the payload does not
    carry — and for nothing that reaches the wire.
    """
    body = _promotion_sql_body()

    for key in ("old_rank_name", "new_rank_name", "old_image_url", "new_image_url"):
        assert f"c.activity_info ->> '{key}'" in body
    assert "main_rank_num_order" in body
    for rendered in (
        "old_rank.name",
        "new_rank.name",
        "old_rank.image_url",
        "new_rank.image_url",
        "sub_rank_image_overrides",
    ):
        assert rendered not in body, (
            f"{rendered!r} is being read live — both belts must stay snapshots"
        )
    assert "a.activity_type = 'rank_changed'" in body
    assert "ORDER BY a.time DESC" in body
    assert "LIMIT 1" in body


def test_latest_promotion_filters_the_newest_row_rather_than_searching_back():
    """The newest change is picked FIRST, then tested for being a promotion.

    Filtering inside the ordered scan would let a superseded older promotion
    resurface after a correction, celebrating a belt the member no longer
    holds. The ``LIMIT 1`` must therefore sit above the promotion predicate,
    not below it.
    """
    body = _promotion_sql_body()

    assert body.index("LIMIT 1") < body.index("new_ladder_position IS NOT NULL")


def test_the_rank_activity_writer_still_logs_every_change():
    """The promotion filter is READ-side only — the log stays complete.

    ``member_activities`` is the audit trail AND the progress anchor that
    member-details and ready-to-promote count classes from, so every rank
    change must keep being written with both leaves fully described. If this
    fails, someone "fixed" the writer instead of the read.
    """
    writer = (RANKS_SQL_DIR / "insert_rank_activity.sql").read_text()

    for key in (
        "old_rank_id",
        "new_rank_id",
        "old_rank_name",
        "new_rank_name",
        "old_sub_index",
        "new_sub_index",
        "old_image_url",
        "new_image_url",
    ):
        assert f"'{key}'" in writer
    assert "WHERE" not in writer.upper(), (
        "the rank-activity writer grew a condition — it must log EVERY rank "
        "change, promotions and demotions alike; celebration is decided on "
        "the read side in member_portal_latest_promotion.sql"
    )


# ── the promotion filter, against the live DB ─────────────────────


@dataclass
class Ladder:
    """A throwaway gym, its 3-rank ladder and one member, all uncommitted."""

    session: AsyncSession
    gym_id: UUID
    member_id: UUID
    ranks: list[UUID]


@pytest.fixture
async def ladder(db_pool) -> AsyncGenerator[Ladder]:
    """A stripes gym with White / Blue / Purple and one member.

    Everything is written inside ONE session that is deliberately never
    committed, so the whole transaction rolls back when the session closes —
    the real SQL runs against real rows, and nothing survives the test.
    """
    async with db_pool.session() as session:
        gym_id = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO gyms (gym_name, sub_rank_type) "
                            "VALUES (:name, 'stripes') RETURNING gym_id"
                        ),
                        {"name": f"ZZ Promotion Gym {uuid4().hex[:8]}"},
                    )
                )
                .mappings()
                .fetchone()["gym_id"]
            )
        )
        ranks: list[UUID] = []
        for position, name in enumerate(("ZZ White", "ZZ Blue", "ZZ Purple")):
            rank_id = (
                (
                    await session.execute(
                        text(
                            "INSERT INTO gym_ranks (gym_id, "
                            "main_rank_num_order, name, "
                            "classes_to_next_major, sub_rank_count) "
                            "VALUES (:g, :p, :n, 40, 5) RETURNING rank_id"
                        ),
                        {"g": str(gym_id), "p": position, "n": name},
                    )
                )
                .mappings()
                .fetchone()["rank_id"]
            )
            ranks.append(UUID(str(rank_id)))
        member_id = UUID(
            str(
                (
                    await session.execute(
                        text(
                            "INSERT INTO members "
                            "(gym_id, first_name, last_name, email) "
                            "VALUES (:g, 'ZZ', 'Promotion', :e) "
                            "RETURNING member_id"
                        ),
                        {
                            "g": str(gym_id),
                            "e": f"zz-promotion-{uuid4().hex[:8]}@test.com",
                        },
                    )
                )
                .mappings()
                .fetchone()["member_id"]
            )
        )
        yield Ladder(session, gym_id, member_id, ranks)
        # No commit — the session's transaction is rolled back on close.


async def _log_change(lad: Ladder, payload: dict, *, minutes: int) -> None:
    """Append one ``rank_changed`` activity ``minutes`` after the epoch base."""
    await lad.session.execute(
        text(
            "INSERT INTO member_activities "
            "(member_id, gym_id, activity_type, activity_info, time) "
            "VALUES (:m, :g, 'rank_changed', CAST(:info AS JSONB), :t)"
        ),
        {
            "m": str(lad.member_id),
            "g": str(lad.gym_id),
            "info": json.dumps(payload),
            "t": PROMOTED_AT + timedelta(minutes=minutes),
        },
    )


async def _read_promotion(lad: Ladder) -> dict | None:
    """Run the REAL read SQL for this member, in the same open transaction."""
    row = (
        await lad.session.execute(
            text(load_sql(SQL_DIR / "member_portal_latest_promotion.sql")),
            {"member_id": str(lad.member_id)},
        )
    ).mappings().fetchone()
    return dict(row) if row else None


def _leaves(
    lad: Ladder,
    *,
    old: tuple[int, int | None] | None,
    new: tuple[int, int | None] | None,
    legacy: bool = False,
) -> dict:
    """A ``rank_changed`` payload for a move between two leaves.

    ``old`` / ``new`` are ``(ladder position, sub index)`` pairs, or ``None``
    for "no leaf on that side" (a first assignment / an unassignment). With
    ``legacy`` the payload carries only the 4 keys written before sub-indices
    and images existed.
    """

    def side(leaf: tuple[int, int | None] | None, prefix: str) -> dict:
        if leaf is None:
            keys = {f"{prefix}_rank_id": None, f"{prefix}_rank_name": None}
            extra = {f"{prefix}_sub_index": None, f"{prefix}_image_url": None}
        else:
            position, sub_index = leaf
            keys = {
                f"{prefix}_rank_id": str(lad.ranks[position]),
                f"{prefix}_rank_name": f"ZZ rank {position}.{sub_index}",
            }
            extra = {
                f"{prefix}_sub_index": sub_index,
                f"{prefix}_image_url": (
                    f"https://cdn.combatden.net/rank/{position}-{sub_index}.png"
                ),
            }
        return keys if legacy else {**keys, **extra}

    return {**side(old, "old"), **side(new, "new")}


async def test_a_main_rank_promotion_surfaces(ladder):
    """Up a main rank is the plainest promotion there is.

    The ladder is ``main_rank_num_order`` ascending, so a higher position
    outranks a lower one — whatever happens to the sub-index, which here even
    goes DOWN (top stripe of White to the bare Blue belt).
    """
    await _log_change(
        ladder, _leaves(ladder, old=(0, 4), new=(1, 0)), minutes=0
    )

    promotion = await _read_promotion(ladder)

    assert promotion is not None
    assert promotion["old_rank_name"] == "ZZ rank 0.4"
    assert promotion["new_rank_name"] == "ZZ rank 1.0"


async def test_a_stripe_promotion_within_one_main_rank_surfaces(ladder):
    """A stripe is a real promotion even though the belt never changed.

    Sub-index ascends within a main rank exactly as the ladder ascends across
    them, so "above" has to account for BOTH levels or every stripe night at a
    BJJ gym would go uncelebrated.
    """
    await _log_change(
        ladder, _leaves(ladder, old=(1, 1), new=(1, 2)), minutes=0
    )

    promotion = await _read_promotion(ladder)

    assert promotion is not None
    assert promotion["new_rank_name"] == "ZZ rank 1.2"


async def test_a_demotion_yields_nothing(ladder):
    """Down a main rank must read exactly like "no promotion"."""
    await _log_change(
        ladder, _leaves(ladder, old=(2, 0), new=(1, 4)), minutes=0
    )

    assert await _read_promotion(ladder) is None


async def test_a_stripe_demotion_yields_nothing(ladder):
    """A stripe taken back is a correction, not something to celebrate."""
    await _log_change(
        ladder, _leaves(ladder, old=(1, 3), new=(1, 1)), minutes=0
    )

    assert await _read_promotion(ladder) is None


async def test_a_lateral_correction_yields_nothing(ladder):
    """Re-writing a member onto the leaf they already hold is not a move.

    Staff fixing an unrelated field can land a same-leaf ``rank_changed``; the
    app must not animate one.
    """
    await _log_change(
        ladder, _leaves(ladder, old=(1, 2), new=(1, 2)), minutes=0
    )

    assert await _read_promotion(ladder) is None


async def test_an_unassignment_yields_nothing(ladder):
    """Taking a member's rank away can never be a promotion.

    It also has no TO leaf at all, so there would be nothing to animate to.
    """
    await _log_change(
        ladder, _leaves(ladder, old=(1, 2), new=None), minutes=0
    )

    assert await _read_promotion(ladder) is None


async def test_a_first_assignment_surfaces_without_a_from_belt(ladder):
    """A member's first belt has no FROM leaf, and still arrives.

    The app renders it as an arrival rather than an animation out of nothing —
    the old side stays null, never fabricated.
    """
    await _log_change(ladder, _leaves(ladder, old=None, new=(0, 0)), minutes=0)

    promotion = await _read_promotion(ladder)

    assert promotion is not None
    assert promotion["old_rank_name"] is None
    assert promotion["old_image_url"] is None
    assert promotion["new_rank_name"] == "ZZ rank 0.0"


async def test_a_legacy_row_surfaces_only_when_the_main_rank_advanced(ladder):
    """Legacy rows fail CLOSED — provable main moves only.

    A row written before the payload carried sub-indices still names both rank
    ids, so a change of MAIN rank is fully provable and celebrates. A change
    WITHIN one main rank is not: with no sub-indices it could equally be a
    stripe promotion or a stripe demotion, and a false "you've been promoted"
    is worse than a missed animation.
    """
    await _log_change(
        ladder,
        _leaves(ladder, old=(1, None), new=(1, None), legacy=True),
        minutes=0,
    )
    assert await _read_promotion(ladder) is None

    await _log_change(
        ladder,
        _leaves(ladder, old=(0, None), new=(1, None), legacy=True),
        minutes=1,
    )
    promotion = await _read_promotion(ladder)
    assert promotion is not None
    assert promotion["new_rank_name"] == "ZZ rank 1.None"
    # Legacy rows carry no images; the client falls back to its themed belt.
    assert promotion["old_image_url"] is None
    assert promotion["new_image_url"] is None


async def test_a_demotion_after_a_promotion_yields_nothing(ladder):
    """Only the NEWEST change is considered — never an earlier promotion.

    The member no longer holds the belt that promotion awarded. The profile
    already shows the belt they DO hold, so re-celebrating the superseded one
    would be a second wrong answer on the same screen.
    """
    await _log_change(
        ladder, _leaves(ladder, old=(1, 4), new=(2, 0)), minutes=0
    )
    assert await _read_promotion(ladder) is not None

    await _log_change(
        ladder, _leaves(ladder, old=(2, 0), new=(1, 4)), minutes=5
    )

    assert await _read_promotion(ladder) is None


async def test_a_rank_deleted_since_the_change_yields_nothing(ladder):
    """A leaf whose ladder position is gone cannot be compared.

    Deleting a rank silently reassigns its members (no activity is logged), so
    an old row can name a rank that no longer exists. Its position is
    unknowable, so the promotion is unprovable — fail closed.
    """
    payload = _leaves(ladder, old=(0, 0), new=(1, 0))
    payload["new_rank_id"] = str(uuid4())
    await _log_change(ladder, payload, minutes=0)

    assert await _read_promotion(ladder) is None


# ── the wire ──────────────────────────────────────────────────────


@pytest.fixture
def portal_service_mock():
    service = MagicMock()
    app.container.member_portal_service.override(service)
    try:
        yield service
    finally:
        app.container.member_portal_service.reset_override()


def _profile_with(row: dict, member_id: UUID, gym_id: UUID) -> MemberPortalProfile:
    detail = _detail(member_id, gym_id)
    return MemberPortalProfile(
        member_id=member_id,
        gym_id=gym_id,
        first_name=detail.first_name,
        last_name=detail.last_name,
        personal_info=detail.personal_info,
        retention=detail.retention,
        latest_promotion=MemberPortalPromotion(**row),
    )


def test_profile_route_serializes_the_promotion_block(
    client, auth_headers, portal_service_mock, fake_gym_id, fake_member_id
):
    """The block reaches the wire on the profile route the app already calls.

    This is the exact contract the member app codes against — field names,
    nullability, and the route that serves them.
    """
    member_id, gym_id = UUID(fake_member_id), UUID(fake_gym_id)
    row = _row()
    portal_service_mock.get_profile = AsyncMock(
        return_value=_profile_with(row, member_id, gym_id)
    )

    resp = client.get(
        f"/api/v1/member/gyms/{fake_gym_id}/members/{fake_member_id}",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    promotion = resp.json()["latest_promotion"]
    assert promotion["activity_id"] == str(row["activity_id"])
    assert promotion["old_rank_name"] == "White · 4 Stripes"
    assert promotion["new_rank_name"] == "Blue"
    assert promotion["old_image_url"] == row["old_image_url"]
    assert promotion["new_image_url"] == row["new_image_url"]


def test_profile_route_omits_nothing_when_there_is_no_promotion(
    client, auth_headers, portal_service_mock, fake_gym_id, fake_member_id
):
    """A never-promoted member serializes an explicit ``null``.

    The key is always present, so the client can distinguish "no promotion"
    from an older backend that didn't know the field.
    """
    member_id, gym_id = UUID(fake_member_id), UUID(fake_gym_id)
    detail = _detail(member_id, gym_id)
    portal_service_mock.get_profile = AsyncMock(
        return_value=MemberPortalProfile(
            member_id=member_id,
            gym_id=gym_id,
            first_name=detail.first_name,
            last_name=detail.last_name,
            personal_info=detail.personal_info,
            retention=detail.retention,
        )
    )

    resp = client.get(
        f"/api/v1/member/gyms/{fake_gym_id}/members/{fake_member_id}",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    assert "latest_promotion" in resp.json()
    assert resp.json()["latest_promotion"] is None
