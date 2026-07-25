"""Unit tests for the member portal router (/api/v1/member/...).

Mocks at the same seam as the other router tests: the ``client`` fixture
(auth + db_pool overridden) plus a per-service container override, so no DB is
touched. What these assert:

* the right GATE runs on every route — ``verify_member_self`` with the PATH
  ``gym_id`` on every gym-scoped route, ``verify_verified_account`` on the
  identity entry point (which has no member to scope yet);
* the hardwired gate semantics actually reach the services (the redemption is
  always ``auto_approve=False``, the feed is always ``rejected=False``, the
  reward catalog is always ``include_inactive=False``) and are not
  client-selectable;
* the router's status-code mapping (service errors → HTTP codes).
"""

from datetime import UTC, date, datetime, time
from unittest.mock import AsyncMock, MagicMock
from uuid import UUID, uuid4

import pytest
from schema.member_reward_redemption import RewardRedemptionStatus
from schema.video import VideoGenre

import src.shared.db_schema_path  # noqa: F401  — resolves ``from schema.*``
from src.checkin.schema.checkin_history_schema import (
    MemberClassHistoryResponse,
    MemberClassHistoryRow,
    MemberClassHistoryStatus,
)
from src.checkin.schema.signup_schema import (
    SignupRemoveResponse,
    SignupResponse,
)
from src.classes.schema.classes_crud_schema import (
    EffectiveClassInstanceListResponse,
)
from src.main import app
from src.member_portal.schema.member_portal_schema import (
    MemberPortalIdentity,
    MemberPortalIdentityListResponse,
    MemberPortalProfile,
    MemberRankProgressResponse,
    RankProgressPoint,
)
from src.members.schema.members_billing_schema import (
    BillingPersonalInfo,
    BillingRetention,
)
from src.rewards.schema.rewards_schema import (
    RedemptionHistoryResponse,
    RedemptionResponse,
    RewardListResponse,
    RewardResponse,
)
from src.videos.schema.video_recs_schema import (
    MemberVideoRec,
    VideoRecClickResponse,
)
from src.videos.schema.videos_schema import GymVideoCard
from src.videos.service.member_video_profile_service import (
    MemberNotInGymError,
)
from src.videos.service.video_rec_click_service import RecNotFoundError


def _base(gym_id: str, member_id: str) -> str:
    return f"/api/v1/member/gyms/{gym_id}/members/{member_id}"


# ── container overrides ───────────────────────────────────────────


@pytest.fixture
def portal_service_mock():
    service = MagicMock()
    app.container.member_portal_service.override(service)
    try:
        yield service
    finally:
        app.container.member_portal_service.reset_override()


@pytest.fixture
def streak_service_mock():
    service = MagicMock()
    app.container.streak_service.override(service)
    try:
        yield service
    finally:
        app.container.streak_service.reset_override()


@pytest.fixture
def history_service_mock():
    service = MagicMock()
    app.container.checkin_history_service.override(service)
    try:
        yield service
    finally:
        app.container.checkin_history_service.reset_override()


@pytest.fixture
def schedule_reader_mock():
    service = MagicMock()
    app.container.classes_schedule_reader_service.override(service)
    try:
        yield service
    finally:
        app.container.classes_schedule_reader_service.reset_override()


@pytest.fixture
def signup_service_mock():
    service = MagicMock()
    app.container.signup_service.override(service)
    try:
        yield service
    finally:
        app.container.signup_service.reset_override()


@pytest.fixture
def rewards_service_mock():
    service = MagicMock()
    app.container.rewards_service.override(service)
    try:
        yield service
    finally:
        app.container.rewards_service.reset_override()


@pytest.fixture
def redemption_service_mock():
    service = MagicMock()
    app.container.rewards_redemption_service.override(service)
    try:
        yield service
    finally:
        app.container.rewards_redemption_service.reset_override()


@pytest.fixture
def videos_service_mock():
    service = MagicMock()
    app.container.videos_service.override(service)
    try:
        yield service
    finally:
        app.container.videos_service.reset_override()


# ── builders ──────────────────────────────────────────────────────


def _profile(gym_id: str, member_id: str) -> MemberPortalProfile:
    return MemberPortalProfile(
        member_id=UUID(member_id),
        gym_id=UUID(gym_id),
        first_name="Ada",
        last_name="Lovelace",
        personal_info=BillingPersonalInfo(email="ada@example.com"),
        retention=BillingRetention(
            last_class=None,
            class_streak_weeks=3,
            points_balance=250,
            videos_watched=7,
        ),
    )


def _reward(gym_id: str, reward_id: str) -> RewardResponse:
    return RewardResponse(
        reward_id=UUID(reward_id),
        gym_id=UUID(gym_id),
        title="Free week",
        point_cost=100,
        image_url="https://cdn.example/x.png",
        price_label="$0",
        is_active=True,
        created_at=datetime.now(UTC),
    )


def _redemption(gym_id: str, member_id: str, reward_id: str) -> RedemptionResponse:
    return RedemptionResponse(
        redemption_id=uuid4(),
        member_id=UUID(member_id),
        reward_id=UUID(reward_id),
        gym_id=UUID(gym_id),
        point_cost=100,
        requested_at=datetime.now(UTC),
        status=RewardRedemptionStatus.pending,
        resolved_at=None,
        points_balance_after=150,
    )


def _video_card() -> GymVideoCard:
    return GymVideoCard(
        video_id="yt123",
        url="https://youtu.be/yt123",
        title="Guard retention",
        thumbnail_url="https://img/x.jpg",
        channel_name="Chan",
        channel_url="https://c",
        channel_avatar_url="https://a",
        relevance_index=0,
        tag=VideoGenre.educational,
    )


# ── identity entry point ──────────────────────────────────────────


def test_list_my_members_uses_verified_account_gate(
    client, auth_headers, auth_mock, portal_service_mock, fake_gym_id,
    fake_user_id,
):
    portal_service_mock.list_members_for_email = AsyncMock(
        return_value=MemberPortalIdentityListResponse(
            members=[
                MemberPortalIdentity(
                    member_id=uuid4(),
                    gym_id=UUID(fake_gym_id),
                    gym_name="Test Gym",
                    gym_address="1200 Combat Ave, Austin, TX 78701",
                    first_name="Ada",
                    last_name="Lovelace",
                )
            ]
        )
    )

    resp = client.get("/api/v1/member/members", headers=auth_headers)

    assert resp.status_code == 200, resp.text
    members = resp.json()["members"]
    assert len(members) == 1
    # The gym's address rides the identity read so the app can show it +
    # an "Open in Maps" link without a second call.
    assert members[0]["gym_address"] == "1200 Combat Ave, Austin, TX 78701"
    auth_mock.verify_verified_account.assert_awaited()
    # The email + caller_id (the JWT sub) both come from the gate, never from
    # the client — the identity query pins the caller's own confirmed account.
    portal_service_mock.list_members_for_email.assert_awaited_once_with(
        "test@example.com", fake_user_id
    )


def test_list_my_members_allows_an_empty_result(
    client, auth_headers, portal_service_mock
):
    portal_service_mock.list_members_for_email = AsyncMock(
        return_value=MemberPortalIdentityListResponse(members=[])
    )

    resp = client.get("/api/v1/member/members", headers=auth_headers)

    assert resp.status_code == 200
    assert resp.json()["members"] == []


# ── profile / streak / history ────────────────────────────────────


def test_get_profile_gates_on_member_self_with_the_path_gym(
    client, auth_headers, auth_mock, portal_service_mock, fake_gym_id, fake_member_id
):
    portal_service_mock.get_profile = AsyncMock(
        return_value=_profile(fake_gym_id, fake_member_id)
    )

    resp = client.get(_base(fake_gym_id, fake_member_id), headers=auth_headers)

    assert resp.status_code == 200, resp.text
    assert resp.json()["retention"]["points_balance"] == 250
    auth_mock.verify_member_self.assert_awaited_once_with(
        UUID(fake_member_id),
        auth_mock.get_current_user.return_value,
        gym_id=UUID(fake_gym_id),
    )


def test_get_profile_maps_missing_member_to_404(
    client, auth_headers, portal_service_mock, fake_gym_id, fake_member_id
):
    portal_service_mock.get_profile = AsyncMock(side_effect=ValueError("nope"))

    resp = client.get(_base(fake_gym_id, fake_member_id), headers=auth_headers)

    assert resp.status_code == 404


def test_rank_progress_gates_and_returns_series(
    client, auth_headers, auth_mock, portal_service_mock, fake_gym_id, fake_member_id
):
    portal_service_mock.get_rank_progress = AsyncMock(
        return_value=MemberRankProgressResponse(
            points=[
                RankProgressPoint(
                    date=date(2026, 7, 1), classes_into_rank=1, classes_needed=2
                ),
                RankProgressPoint(
                    date=date(2026, 7, 8), classes_into_rank=0, classes_needed=2
                ),
            ]
        )
    )

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/rank-progress", headers=auth_headers
    )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert [p["classes_into_rank"] for p in body["points"]] == [1, 0]
    assert body["points"][0]["classes_needed"] == 2
    portal_service_mock.get_rank_progress.assert_awaited_once_with(
        UUID(fake_member_id), UUID(fake_gym_id)
    )
    auth_mock.verify_member_self.assert_awaited_once_with(
        UUID(fake_member_id),
        auth_mock.get_current_user.return_value,
        gym_id=UUID(fake_gym_id),
    )


def test_rank_progress_allows_an_empty_series(
    client, auth_headers, portal_service_mock, fake_gym_id, fake_member_id
):
    portal_service_mock.get_rank_progress = AsyncMock(
        return_value=MemberRankProgressResponse(points=[])
    )

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/rank-progress", headers=auth_headers
    )

    assert resp.status_code == 200
    assert resp.json()["points"] == []


def test_get_streak_gates_and_returns_weeks(
    client, auth_headers, auth_mock, streak_service_mock, fake_gym_id, fake_member_id
):
    streak_service_mock.get_streak = AsyncMock(return_value=4)

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/streak", headers=auth_headers
    )

    assert resp.status_code == 200, resp.text
    assert resp.json()["class_streak_weeks"] == 4
    auth_mock.verify_member_self.assert_awaited_once_with(
        UUID(fake_member_id),
        auth_mock.get_current_user.return_value,
        gym_id=UUID(fake_gym_id),
    )


def test_class_history_gates_and_paginates(
    client, auth_headers, auth_mock, history_service_mock, fake_gym_id, fake_member_id
):
    reserved = MemberClassHistoryRow(
        class_id=uuid4(),
        class_name="Fundamentals",
        image_url="https://cdn.example/f.png",
        original_date=date(2026, 8, 1),
        original_time=time(18, 0),
        duration_minutes=60,
        points_worth=55,
        occurred_at=None,
        status=MemberClassHistoryStatus.reserved,
    )
    attended = MemberClassHistoryRow(
        class_id=uuid4(),
        class_name="Sparring",
        image_url="https://cdn.example/s.png",
        original_date=date(2026, 7, 1),
        original_time=time(19, 0),
        duration_minutes=90,
        points_worth=75,
        occurred_at=datetime(2026, 7, 1, 19, 0, tzinfo=UTC),
        status=MemberClassHistoryStatus.attended,
    )
    history_service_mock.get_history = AsyncMock(
        return_value=MemberClassHistoryResponse(
            upcoming=[reserved], history=[attended], has_more=False
        )
    )

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/class-history?limit=5&offset=10",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    history_service_mock.get_history.assert_awaited_once_with(
        UUID(fake_member_id), UUID(fake_gym_id), limit=5, offset=10
    )
    auth_mock.verify_member_self.assert_awaited()
    # points_worth rides through the response contract on both lists — the
    # potential award on a reservation, the earned points on an attended row.
    body = resp.json()
    assert body["upcoming"][0]["points_worth"] == 55
    assert body["history"][0]["points_worth"] == 75


def test_class_history_rejects_an_out_of_range_limit(
    client, auth_headers, history_service_mock, fake_gym_id, fake_member_id
):
    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/class-history?limit=5000",
        headers=auth_headers,
    )

    assert resp.status_code == 422


# ── schedule board ────────────────────────────────────────────────


def test_classes_board_gates_and_delegates(
    client, auth_headers, auth_mock, schedule_reader_mock, fake_gym_id, fake_member_id
):
    schedule_reader_mock.list_effective_instances = AsyncMock(
        return_value=EffectiveClassInstanceListResponse(items=[])
    )

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/classes"
        "?start_date=2026-07-01&end_date=2026-07-07",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    schedule_reader_mock.list_effective_instances.assert_awaited_once_with(
        UUID(fake_gym_id), date(2026, 7, 1), date(2026, 7, 7)
    )
    auth_mock.verify_member_self.assert_awaited_once_with(
        UUID(fake_member_id),
        auth_mock.get_current_user.return_value,
        gym_id=UUID(fake_gym_id),
    )


# ── sign-ups ──────────────────────────────────────────────────────


def _signup_body() -> dict:
    return {
        "class_id": str(uuid4()),
        "occurrence_date": "2026-07-03",
        "occurrence_time": "18:30:00",
    }


def test_create_signup_uses_the_path_member_not_the_body(
    client, auth_headers, auth_mock, signup_service_mock, fake_gym_id, fake_member_id
):
    signup_service_mock.create = AsyncMock(
        return_value=SignupResponse(signup_id=uuid4(), already_signed_up=False)
    )
    body = _signup_body()
    # An attacker-shaped body: the extra ids must be ignored entirely.
    body["member_id"] = str(uuid4())
    body["gym_id"] = str(uuid4())

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/signup",
        json=body,
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    signup_service_mock.create.assert_awaited_once_with(
        UUID(fake_member_id),
        UUID(fake_gym_id),
        UUID(body["class_id"]),
        date(2026, 7, 3),
        time(18, 30),
    )
    auth_mock.verify_member_self.assert_awaited()


def test_create_signup_maps_full_class_to_400(
    client, auth_headers, signup_service_mock, fake_gym_id, fake_member_id
):
    signup_service_mock.create = AsyncMock(side_effect=ValueError("Class is full"))

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/signup",
        json=_signup_body(),
        headers=auth_headers,
    )

    assert resp.status_code == 400
    assert resp.json()["detail"] == "Class is full"


def test_create_signup_maps_missing_class_to_404(
    client, auth_headers, signup_service_mock, fake_gym_id, fake_member_id
):
    signup_service_mock.create = AsyncMock(side_effect=ValueError("Class not found"))

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/signup",
        json=_signup_body(),
        headers=auth_headers,
    )

    assert resp.status_code == 404


def test_remove_signup_gates_and_delegates(
    client, auth_headers, auth_mock, signup_service_mock, fake_gym_id, fake_member_id
):
    signup_service_mock.remove = AsyncMock(
        return_value=SignupRemoveResponse(removed=True)
    )
    class_id = str(uuid4())

    resp = client.delete(
        f"{_base(fake_gym_id, fake_member_id)}/signup"
        f"?class_id={class_id}&occurrence_date=2026-07-03&occurrence_time=18:30:00",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    assert resp.json()["removed"] is True
    signup_service_mock.remove.assert_awaited_once_with(
        UUID(fake_member_id),
        UUID(fake_gym_id),
        UUID(class_id),
        date(2026, 7, 3),
        time(18, 30),
    )
    auth_mock.verify_member_self.assert_awaited()


# ── rewards ───────────────────────────────────────────────────────


def test_reward_catalog_never_includes_inactive(
    client, auth_headers, auth_mock, rewards_service_mock, fake_gym_id, fake_member_id
):
    rewards_service_mock.list_rewards = AsyncMock(
        return_value=RewardListResponse(items=[])
    )

    # Even when the client tries to ask for them.
    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/rewards?include_inactive=true",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    rewards_service_mock.list_rewards.assert_awaited_once_with(
        UUID(fake_gym_id), include_inactive=False
    )
    auth_mock.verify_member_self.assert_awaited()


def test_redemption_history_gates_and_delegates(
    client,
    auth_headers,
    auth_mock,
    redemption_service_mock,
    fake_gym_id,
    fake_member_id,
):
    redemption_service_mock.history = AsyncMock(
        return_value=RedemptionHistoryResponse(items=[])
    )

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/redemptions", headers=auth_headers
    )

    assert resp.status_code == 200, resp.text
    redemption_service_mock.history.assert_awaited_once_with(UUID(fake_member_id))
    auth_mock.verify_member_self.assert_awaited()


def test_redeem_is_always_pending_never_auto_approved(
    client,
    auth_headers,
    auth_mock,
    rewards_service_mock,
    redemption_service_mock,
    fake_gym_id,
    fake_member_id,
    fake_reward_id,
):
    rewards_service_mock.get_reward = AsyncMock(
        return_value=_reward(fake_gym_id, fake_reward_id)
    )
    redemption_service_mock.redeem = AsyncMock(
        return_value=_redemption(fake_gym_id, fake_member_id, fake_reward_id)
    )

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/rewards/{fake_reward_id}/redeem",
        headers=auth_headers,
    )

    assert resp.status_code == 201, resp.text
    assert resp.json()["status"] == "pending"
    redemption_service_mock.redeem.assert_awaited_once_with(
        UUID(fake_member_id), UUID(fake_reward_id), auto_approve=False
    )
    auth_mock.verify_member_self.assert_awaited()


def test_redeem_404s_a_reward_from_another_gym_without_debiting(
    client,
    auth_headers,
    rewards_service_mock,
    redemption_service_mock,
    fake_gym_id,
    fake_member_id,
    fake_reward_id,
):
    rewards_service_mock.get_reward = AsyncMock(
        return_value=_reward(str(uuid4()), fake_reward_id)
    )
    redemption_service_mock.redeem = AsyncMock()

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/rewards/{fake_reward_id}/redeem",
        headers=auth_headers,
    )

    assert resp.status_code == 404
    redemption_service_mock.redeem.assert_not_awaited()


def test_redeem_maps_insufficient_points_to_400(
    client,
    auth_headers,
    rewards_service_mock,
    redemption_service_mock,
    fake_gym_id,
    fake_member_id,
    fake_reward_id,
):
    rewards_service_mock.get_reward = AsyncMock(
        return_value=_reward(fake_gym_id, fake_reward_id)
    )
    redemption_service_mock.redeem = AsyncMock(
        side_effect=ValueError("Redemption rejected: insufficient points")
    )

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/rewards/{fake_reward_id}/redeem",
        headers=auth_headers,
    )

    assert resp.status_code == 400


# ── videos ────────────────────────────────────────────────────────


def test_video_feed_is_always_the_served_list_and_personalized(
    client, auth_headers, auth_mock, videos_service_mock, fake_gym_id, fake_member_id
):
    videos_service_mock.load_feed_page = AsyncMock(return_value=([_video_card()], 1))

    # ``rejected`` is not a parameter here — passing it must change nothing.
    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/videos?rejected=true&limit=5",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    videos_service_mock.load_feed_page.assert_awaited_once_with(
        UUID(fake_gym_id),
        rejected=False,
        video_type=None,
        big_group=None,
        member_id=UUID(fake_member_id),
        limit=5,
        offset=0,
    )
    auth_mock.verify_member_self.assert_awaited()


def test_video_feed_rejects_both_genre_filters(
    client, auth_headers, videos_service_mock, fake_gym_id, fake_member_id
):
    videos_service_mock.load_feed_page = AsyncMock()

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/videos"
        "?video_type=analysis&big_group=educational",
        headers=auth_headers,
    )

    assert resp.status_code == 400
    videos_service_mock.load_feed_page.assert_not_awaited()


def test_video_rec_returns_the_pick(
    client, auth_headers, auth_mock, videos_service_mock, fake_gym_id, fake_member_id
):
    videos_service_mock.get_video_rec = AsyncMock(
        return_value=MemberVideoRec(
            rec_id=uuid4(), category=VideoGenre.educational, video=_video_card()
        )
    )

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/video-rec", headers=auth_headers
    )

    assert resp.status_code == 200, resp.text
    assert resp.json()["video"]["video_id"] == "yt123"
    auth_mock.verify_member_self.assert_awaited()


def test_video_rec_404s_when_nothing_is_available(
    client, auth_headers, videos_service_mock, fake_gym_id, fake_member_id
):
    videos_service_mock.get_video_rec = AsyncMock(return_value=None)

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/video-rec", headers=auth_headers
    )

    assert resp.status_code == 404


def test_video_rec_404s_a_member_not_in_the_gym(
    client, auth_headers, videos_service_mock, fake_gym_id, fake_member_id
):
    videos_service_mock.get_video_rec = AsyncMock(
        side_effect=MemberNotInGymError("Member not in gym")
    )

    resp = client.get(
        f"{_base(fake_gym_id, fake_member_id)}/video-rec", headers=auth_headers
    )

    assert resp.status_code == 404


def test_rec_click_delegates_and_gates(
    client, auth_headers, auth_mock, videos_service_mock, fake_gym_id, fake_member_id
):
    rec_id = uuid4()
    videos_service_mock.record_rec_click = AsyncMock(
        return_value=VideoRecClickResponse(clicked=True, video_id="yt123")
    )

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/video-rec/{rec_id}/click",
        headers=auth_headers,
    )

    assert resp.status_code == 200, resp.text
    videos_service_mock.record_rec_click.assert_awaited_once_with(
        UUID(fake_gym_id), UUID(fake_member_id), rec_id
    )
    auth_mock.verify_member_self.assert_awaited()


def test_rec_click_404s_an_unknown_rec(
    client, auth_headers, videos_service_mock, fake_gym_id, fake_member_id
):
    videos_service_mock.record_rec_click = AsyncMock(
        side_effect=RecNotFoundError("Recommendation not found")
    )

    resp = client.post(
        f"{_base(fake_gym_id, fake_member_id)}/video-rec/{uuid4()}/click",
        headers=auth_headers,
    )

    assert resp.status_code == 404
