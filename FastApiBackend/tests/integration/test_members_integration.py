"""Integration tests for the members domain — OG (CRM) contract.

Covers the highest-value read paths against the live backend:
- POST /api/v1/members/list  (all / trial / frozen / overdue views)
- GET  /api/v1/members/counts
- GET  /api/v1/members/{member_id}

Contract source of truth: Database/openapi.json

Key OG changes from the old demo contract:
- POST /list takes a single 'view' (not just gym_id); views are
  'all' / 'trial' / 'frozen' / 'overdue' (no 'active'/'inactive'). The view
  and the filters are independent — the backend applies both as given and
  does no view/filter reconciliation.
- Response shape: {view, filters, data:[...rows]}  (no 'items'/'total').
- Rows are discriminated on the 'view' field (AllViewRow / TrialViewRow /
  FrozenViewRow / OverdueViewRow) — not a uniform MemberListItem.
- GET /counts returns {active, trial, frozen, overdue} — no 'all' bucket;
  'all' is not the sum of the other buckets (it is the full roster count).
- GET /{member_id} returns MemberBillingDetailResponse (not the old
  MemberDetailResponse with trial_start_date etc.).
"""

import uuid

import httpx
import pytest

BASE = "/api/v1/members"

# Valid MembersListView values per OpenAPI enum
VALID_VIEWS = {"all", "trial", "frozen", "overdue"}

# Valid CrmMemberStatus values per OpenAPI enum
VALID_CRM_STATUSES = {
    "active", "trial", "frozen", "cancelled", "ended", "overdue", "no_membership"
}


# ── Helpers ──────────────────────────────────────────────────────────────────


def _list_payload(
    gym_id: str,
    view: str = "all",
    **kwargs,
) -> dict:
    """Build a minimal CrmMembersListRequest body.

    The body is just gym_id + view (+ optional filters / pagination). The
    view names the row shape and is honored as-is; any filters apply on top
    independently (no reconciliation).
    """
    payload: dict = {
        "gym_id": gym_id,
        "view": view,
    }
    payload.update(kwargs)
    return payload


def _assert_all_view_row(item: dict) -> None:
    """Assert a single AllViewRow matches the OpenAPI contract."""
    assert item.get("view") == "all", f"AllViewRow.view != 'all': {item.get('view')!r}"
    assert "member_id" in item, "AllViewRow missing member_id"
    assert "name" in item, "AllViewRow missing name"
    assert "membership_status" in item, "AllViewRow missing membership_status"
    assert item["membership_status"] in VALID_CRM_STATUSES, (
        f"AllViewRow.membership_status={item['membership_status']!r} "
        f"not in {VALID_CRM_STATUSES}"
    )
    assert "membership_text" in item, "AllViewRow missing membership_text"


def _assert_trial_view_row(item: dict) -> None:
    """Assert a single TrialViewRow matches the OpenAPI contract."""
    assert item.get("view") == "trial", f"TrialViewRow.view != 'trial': {item.get('view')!r}"
    assert "member_id" in item, "TrialViewRow missing member_id"
    assert "name" in item, "TrialViewRow missing name"
    assert "days_remaining" in item, "TrialViewRow missing days_remaining"
    assert isinstance(item["days_remaining"], int), "TrialViewRow.days_remaining not int"
    assert "start_date" in item, "TrialViewRow missing start_date"
    assert "end_date" in item, "TrialViewRow missing end_date"


def _assert_frozen_view_row(item: dict) -> None:
    """Assert a single FrozenViewRow matches the OpenAPI contract."""
    assert item.get("view") == "frozen", f"FrozenViewRow.view != 'frozen': {item.get('view')!r}"
    assert "member_id" in item, "FrozenViewRow missing member_id"
    assert "name" in item, "FrozenViewRow missing name"
    assert "freeze_start" in item, "FrozenViewRow missing freeze_start"
    assert "days_until_unfrozen" in item, "FrozenViewRow missing days_until_unfrozen"
    assert isinstance(item["days_until_unfrozen"], int), (
        "FrozenViewRow.days_until_unfrozen not int"
    )
    assert "freeze_end" in item, "FrozenViewRow missing freeze_end"
    assert "price" in item, "FrozenViewRow missing price"


def _assert_overdue_view_row(item: dict) -> None:
    """Assert a single OverdueViewRow matches the OpenAPI contract."""
    assert item.get("view") == "overdue", (
        f"OverdueViewRow.view != 'overdue': {item.get('view')!r}"
    )
    assert "member_id" in item, "OverdueViewRow missing member_id"
    assert "name" in item, "OverdueViewRow missing name"
    assert "membership_text" in item, "OverdueViewRow missing membership_text"
    assert "days_late" in item, "OverdueViewRow missing days_late"
    assert isinstance(item["days_late"], int), "OverdueViewRow.days_late not int"


# ── POST /api/v1/members/list — view: all ────────────────────────────────────


class TestListMembersAll:
    def test_returns_200(self, api: httpx.Client, gym_id: str) -> None:
        resp = api.post(f"{BASE}/list", json=_list_payload(gym_id, "all"))
        assert resp.status_code == 200, (
            f"POST /list (all) returned {resp.status_code}: {resp.text}"
        )

    def test_response_shape(self, api: httpx.Client, gym_id: str) -> None:
        resp = api.post(f"{BASE}/list", json=_list_payload(gym_id, "all"))
        assert resp.status_code == 200
        body = resp.json()
        assert "view" in body, "response missing 'view'"
        assert "filters" in body, "response missing 'filters'"
        assert "data" in body, "response missing 'data'"
        assert isinstance(body["data"], list), "'data' is not a list"
        assert body["view"] == "all", f"echoed view={body['view']!r}, expected 'all'"

    def test_all_view_rows_have_correct_shape(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every row in the 'all' view must be an AllViewRow with valid CrmMemberStatus."""
        resp = api.post(f"{BASE}/list", json=_list_payload(gym_id, "all"))
        assert resp.status_code == 200, (
            f"POST /list (all) returned {resp.status_code}: {resp.text}"
        )
        for item in resp.json()["data"]:
            _assert_all_view_row(item)

    def test_pagination_count_respected(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "all", count=5, start_index=0),
        )
        assert resp.status_code == 200
        assert len(resp.json()["data"]) <= 5, "count=5 returned more than 5 rows"

    def test_filters_echoed_back(self, api: httpx.Client, gym_id: str) -> None:
        resp = api.post(f"{BASE}/list", json=_list_payload(gym_id, "all"))
        assert resp.status_code == 200
        filters = resp.json()["filters"]
        assert "membership_status" in filters, "filters missing membership_status"
        assert "plan_ids" in filters, "filters missing plan_ids"
        assert "date_range" in filters, "filters missing date_range"
        assert "name" in filters, "filters missing name"


# ── POST /api/v1/members/list — view: trial ──────────────────────────────────


class TestListMembersTrial:
    def test_returns_200(self, api: httpx.Client, gym_id: str) -> None:
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "trial"),
        )
        assert resp.status_code == 200, (
            f"POST /list (trial) returned {resp.status_code}: {resp.text}"
        )

    def test_all_items_are_trial_rows(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every row returned for the trial view must be a TrialViewRow."""
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "trial"),
        )
        assert resp.status_code == 200
        for item in resp.json()["data"]:
            _assert_trial_view_row(item)


# ── POST /api/v1/members/list — view: frozen ─────────────────────────────────


class TestListMembersFrozen:
    def test_returns_200(self, api: httpx.Client, gym_id: str) -> None:
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "frozen"),
        )
        assert resp.status_code == 200, (
            f"POST /list (frozen) returned {resp.status_code}: {resp.text}"
        )

    def test_all_items_are_frozen_rows(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every row returned for the frozen view must be a FrozenViewRow."""
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "frozen"),
        )
        assert resp.status_code == 200
        for item in resp.json()["data"]:
            _assert_frozen_view_row(item)


# ── POST /api/v1/members/list — view: overdue ────────────────────────────────


class TestListMembersOverdue:
    def test_returns_200(self, api: httpx.Client, gym_id: str) -> None:
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "overdue"),
        )
        assert resp.status_code == 200, (
            f"POST /list (overdue) returned {resp.status_code}: {resp.text}"
        )

    def test_all_items_are_overdue_rows(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """Every row returned for the overdue view must be an OverdueViewRow."""
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "overdue"),
        )
        assert resp.status_code == 200
        for item in resp.json()["data"]:
            _assert_overdue_view_row(item)


# ── POST /api/v1/members/list — validation ───────────────────────────────────


class TestListMembersValidation:
    def test_invalid_view_returns_422(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """A view value outside the MembersListView enum must return 422."""
        resp = api.post(
            f"{BASE}/list",
            json={
                "gym_id": gym_id,
                "view": "active",  # not in MembersListView enum
            },
        )
        # 'active' is not a valid MembersListView (only all/trial/frozen/overdue)
        assert resp.status_code == 422, (
            f"Invalid view='active' should return 422, got {resp.status_code}"
        )

    def test_missing_view_returns_422(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        """view is required; omitting it must return 422."""
        resp = api.post(
            f"{BASE}/list",
            json={"gym_id": gym_id},
        )
        assert resp.status_code == 422, (
            f"Missing view should return 422, got {resp.status_code}"
        )

    def test_missing_gym_id_returns_422(self, api: httpx.Client) -> None:
        resp = api.post(
            f"{BASE}/list",
            json={"view": "all"},
        )
        assert resp.status_code == 422

    def test_wrong_gym_id_returns_403(self, api: httpx.Client) -> None:
        resp = api.post(
            f"{BASE}/list",
            json={
                "gym_id": str(uuid.uuid4()),
                "view": "all",
            },
        )
        assert resp.status_code == 403, (
            f"Random gym_id should be 403 Forbidden, got {resp.status_code}"
        )


# ── GET /api/v1/members/counts ───────────────────────────────────────────────


class TestMemberCounts:
    def test_returns_200(self, api: httpx.Client, gym_id: str) -> None:
        resp = api.get(f"{BASE}/counts", params={"gym_id": gym_id})
        assert resp.status_code == 200, (
            f"GET /counts returned {resp.status_code}: {resp.text}"
        )

    def test_response_shape(self, api: httpx.Client, gym_id: str) -> None:
        """MembersListTotalCounts has active/trial/frozen/overdue — no 'all' bucket."""
        resp = api.get(f"{BASE}/counts", params={"gym_id": gym_id})
        assert resp.status_code == 200
        body = resp.json()
        for field in ("active", "trial", "frozen", "overdue"):
            assert field in body, f"counts missing '{field}'"
            assert isinstance(body[field], int), f"counts.{field} not int"
        assert "all" not in body, (
            "counts must NOT have an 'all' key — OG contract has active/trial/frozen/overdue"
        )

    def test_all_counts_are_nonnegative(
        self, api: httpx.Client, gym_id: str
    ) -> None:
        resp = api.get(f"{BASE}/counts", params={"gym_id": gym_id})
        assert resp.status_code == 200
        body = resp.json()
        for field in ("active", "trial", "frozen", "overdue"):
            assert body[field] >= 0, f"counts.{field} is negative: {body[field]}"

    def test_wrong_gym_id_returns_403(self, api: httpx.Client) -> None:
        resp = api.get(
            f"{BASE}/counts",
            params={"gym_id": str(uuid.uuid4())},
        )
        assert resp.status_code == 403


# ── GET /api/v1/members/{member_id} ─────────────────────────────────────────


class TestGetMemberDetail:
    @pytest.fixture(scope="class")
    def member_id(self, api: httpx.Client, gym_id: str) -> str:
        """Pull a real member_id from /list (all view)."""
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "all", count=1, start_index=0),
        )
        if resp.status_code != 200:
            pytest.skip(f"Cannot get member_id: /list returned {resp.status_code}")
        items = resp.json().get("data", [])
        if not items:
            pytest.skip("No members in seed data for this gym")
        return items[0]["member_id"]

    def test_returns_200(
        self, api: httpx.Client, member_id: str
    ) -> None:
        """GET /{member_id} returns 200 with the OG MemberBillingDetailResponse."""
        resp = api.get(f"{BASE}/{member_id}")
        assert resp.status_code == 200, (
            f"GET /{member_id} returned {resp.status_code}: {resp.text}"
        )

    def test_response_shape(
        self, api: httpx.Client, member_id: str
    ) -> None:
        """MemberBillingDetailResponse required fields per OpenAPI schema."""
        resp = api.get(f"{BASE}/{member_id}")
        assert resp.status_code == 200
        body = resp.json()
        required_fields = [
            "member_id", "gym_id", "first_name", "last_name",
            "membership_overview",
            "total_monthly_recurring_price",
            "total_membership_count",
            "personal_info",
            "memberships",
            "retention",
        ]
        for field in required_fields:
            assert field in body, f"MemberBillingDetailResponse missing '{field}'"

    def test_memberships_is_list(
        self, api: httpx.Client, member_id: str
    ) -> None:
        resp = api.get(f"{BASE}/{member_id}")
        assert resp.status_code == 200
        assert isinstance(resp.json()["memberships"], list)

    def test_retention_shape(
        self, api: httpx.Client, member_id: str
    ) -> None:
        resp = api.get(f"{BASE}/{member_id}")
        assert resp.status_code == 200
        retention = resp.json()["retention"]
        for field in ("class_streak_weeks", "points_balance", "videos_watched"):
            assert field in retention, f"retention missing '{field}'"

    def test_unknown_member_returns_404(self, api: httpx.Client) -> None:
        resp = api.get(f"{BASE}/{uuid.uuid4()}")
        assert resp.status_code in (403, 404), (
            f"Unknown member should return 403 or 404, got {resp.status_code}"
        )


# ── GET /api/v1/members/{member_id}/billing ──────────────────────────────────


class TestGetMemberBilling:
    @pytest.fixture(scope="class")
    def member_id(self, api: httpx.Client, gym_id: str) -> str:
        """Pull a real member_id from /list (all view)."""
        resp = api.post(
            f"{BASE}/list",
            json=_list_payload(gym_id, "all", count=1, start_index=0),
        )
        if resp.status_code != 200:
            pytest.skip(f"Cannot get member_id: /list returned {resp.status_code}")
        items = resp.json().get("data", [])
        if not items:
            pytest.skip("No members in seed data for this gym")
        return items[0]["member_id"]

    def test_returns_200(
        self, api: httpx.Client, member_id: str
    ) -> None:
        """GET /{member_id}/billing returns 200 for a valid member.

        Unlike the old demo contract, GET /{member_id}/billing is now served
        by the same MembersBillingDetailService as GET /{member_id} and does
        not require a separate billing profile row. Any seeded member returns
        200; 404 only if the member itself doesn't exist.
        """
        resp = api.get(f"{BASE}/{member_id}/billing")
        assert resp.status_code == 200, (
            f"GET /{member_id}/billing returned {resp.status_code}: {resp.text}"
        )

    def test_response_shape_when_200(
        self, api: httpx.Client, member_id: str
    ) -> None:
        resp = api.get(f"{BASE}/{member_id}/billing")
        assert resp.status_code == 200
        body = resp.json()
        required_fields = [
            "member_id", "gym_id", "first_name", "last_name",
            "membership_overview",
            "total_monthly_recurring_price",
            "total_membership_count",
            "personal_info",
            "memberships",
            "retention",
        ]
        for field in required_fields:
            assert field in body, f"MemberBillingDetailResponse missing '{field}'"

    def test_retention_shape_when_200(
        self, api: httpx.Client, member_id: str
    ) -> None:
        resp = api.get(f"{BASE}/{member_id}/billing")
        assert resp.status_code == 200
        retention = resp.json().get("retention", {})
        for field in ("class_streak_weeks", "points_balance", "videos_watched"):
            assert field in retention, f"BillingRetention missing '{field}'"
