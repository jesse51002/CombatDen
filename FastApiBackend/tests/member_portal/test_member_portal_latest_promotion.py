"""The profile's ``latest_promotion`` block — the promotion animation's data.

The member app plays an old-belt → new-belt animation ONCE per new promotion,
driven by its own local watermark. That contract puts two demands on the
backend, and this file locks both:

1. **Both belts arrive resolved.** The client holds no prior rank, so the row
   must carry the FROM leaf as well as the TO leaf. The values come straight
   out of the activity's own snapshot — never a live join to ``gym_ranks``,
   whose image columns are user-writable.
2. **It degrades, it never fails.** A member who has never been promoted gets
   ``null``; a row written before the payload carried images gets null URLs and
   the client falls back to its themed belt. Nothing is backfilled.

It rides the PROFILE read the celebration screen already makes, so there is no
extra round trip — and it is member-portal-private: ``MembersBillingDetailService``
(shared with the CRM member-detail card) is not touched.

Hermetic: the DB pool and the billing-detail service are doubles.
"""

from datetime import UTC, datetime
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest

from src.main import app
from src.member_portal.schema.member_portal_schema import (
    MemberPortalProfile,
    MemberPortalPromotion,
)
from src.member_portal.service.member_portal_service import MemberPortalService
from src.members.schema.members_billing_schema import (
    BillingPersonalInfo,
    BillingRetention,
)

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


def test_latest_promotion_sql_reads_the_snapshot_not_a_live_join():
    """The read takes both belts from ``activity_info``, never ``gym_ranks``.

    A live join would let a gym re-uploading its belt art rewrite what every
    past promotion looked like. It is also scoped to ``rank_changed`` and
    returns exactly the newest row.
    """
    from src.member_portal import SQL_DIR  # noqa: PLC0415

    sql = (SQL_DIR / "member_portal_latest_promotion.sql").read_text()
    body = "\n".join(
        line for line in sql.splitlines() if not line.lstrip().startswith("--")
    )

    assert "gym_ranks" not in body
    for key in ("old_rank_name", "new_rank_name", "old_image_url", "new_image_url"):
        assert f"a.activity_info ->> '{key}'" in body
    assert "a.activity_type = 'rank_changed'" in body
    assert "ORDER BY a.time DESC" in body
    assert "LIMIT 1" in body


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
