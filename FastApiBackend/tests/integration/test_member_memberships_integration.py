"""Integration tests for the member_memberships domain.

All endpoints under /api/v1/member_memberships/ are Stripe-coupled.
Strategy:
  - 401 guard: hit every endpoint with no credentials.
  - 422 validation: hit endpoints with structurally invalid bodies and
    assert the serialisation layer rejects them before any DB/Stripe work.
  - 404 not-found: hit write endpoints with valid auth but nonexistent
    IDs; expect 404 with a legible detail string (DB lookup, no Stripe).
  - Preview paths: call /preview, /cancel/preview, and
    /discounts/add (preview=true); expect 404 (no membership) or 400 (no plan).
    These are the safe dry-run paths — any 500 is a real backend bug.
    (Reprice has no preview endpoint — it is direct/synchronous.)
  - NO real Stripe charges are driven. charge-card, mark-paid-cash,
    start, cancel, freeze, unfreeze, reprice (PUT /price), and update_discounts
    are tested only through the validation and 404 layers.

Seed state assumed:
  - owner1@test.com owns gym 21636369-8b52-9b4a-97b7-50923ceb3ffd (the one seeded gym)
  - Members exist in that gym (e.g. 1afa89ea-e596-4cfa-a333-6efd691dcf5a)
  - No membership_plans, membership_plan_prices, or member_memberships
    rows exist (the seed is bare for this domain)
  - No member_billing_profile rows exist (no Stripe customer IDs)
"""

from uuid import uuid4

from tests.seed_constants import SEEDED_GYM_ID

GYM_ID = SEEDED_GYM_ID
MEMBER_ID = "1afa89ea-e596-4cfa-a333-6efd691dcf5a"  # Tanya Harrison (stale — old seed)

# Nonexistent UUIDs used as placeholders throughout
_NULL_ITEM_ID = "00000000-0000-0000-0000-000000000001"
_NULL_PLAN_ID = "00000000-0000-0000-0000-000000000002"
_NULL_PRICE_ID = "00000000-0000-0000-0000-000000000003"
_IKEY = "00000000-0000-0000-0000-000000000099"

BASE = "/api/v1/member_memberships"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _idempotency_key() -> str:
    """Fresh UUID string — prevents Stripe idempotency collisions."""
    return str(uuid4())


# ---------------------------------------------------------------------------
# 401 — no credentials
# ---------------------------------------------------------------------------


class TestUnauthenticated:
    """Every endpoint must reject requests with no Bearer token."""

    def test_cancel_no_auth(self, api):
        """DELETE / without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.delete(
            f"{BASE}/",
            params={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_freeze_no_auth(self, api):
        """POST /freeze without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/freeze",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "freeze_months": 1,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_unfreeze_no_auth(self, api):
        """POST /unfreeze without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/unfreeze",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_start_no_auth(self, api):
        """POST / without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "plan_id": _NULL_PLAN_ID,
                "price_id": _NULL_PRICE_ID,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_preview_start_no_auth(self, api):
        """POST /preview without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/preview",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "plan_id": _NULL_PLAN_ID,
                "price_id": _NULL_PRICE_ID,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_preview_cancel_no_auth(self, api):
        """POST /cancel/preview without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/cancel/preview",
            params={"item_id": _NULL_ITEM_ID, "member_id": MEMBER_ID},
        )
        assert r.status_code == 401, r.text

    def test_price_no_auth(self, api):
        """PUT /price without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.put(
            f"{BASE}/price",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_discounts_no_auth(self, api):
        """POST /discounts/add without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/discounts/add",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "discount_ids": [_NULL_PLAN_ID],
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_preview_discounts_no_auth(self, api):
        """POST /discounts/remove without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/discounts/remove",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "applied_ids": [_NULL_PLAN_ID],
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text

    def test_mark_paid_cash_no_auth(self, api):
        """POST /mark-paid-cash without auth returns 401."""
        client = api.__class__(
            base_url=str(api.base_url),
            timeout=api.timeout,
        )
        r = client.post(
            f"{BASE}/mark-paid-cash",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 401, r.text


# ---------------------------------------------------------------------------
# 422 — Pydantic validation errors (auth not needed — FastAPI rejects first)
# ---------------------------------------------------------------------------


class TestValidation:
    """FastAPI/Pydantic should reject structurally invalid payloads with 422."""

    def test_freeze_missing_required_fields(self, api):
        """POST /freeze with only member_id returns 422 listing missing fields."""
        r = api.post(
            f"{BASE}/freeze",
            json={"member_id": MEMBER_ID},
        )
        assert r.status_code == 422, r.text
        detail = r.json()["detail"]
        missing_fields = {err["loc"][-1] for err in detail if err["type"] == "missing"}
        assert "gym_id" in missing_fields
        assert "freeze_months" in missing_fields
        assert "idempotency_key" in missing_fields

    def test_freeze_months_must_be_positive(self, api):
        """POST /freeze with freeze_months=0 returns 422 (gt constraint)."""
        r = api.post(
            f"{BASE}/freeze",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "freeze_months": 0,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 422, r.text
        detail = r.json()["detail"]
        types = {err["type"] for err in detail}
        assert "greater_than" in types

    def test_start_missing_plan_id(self, api):
        """POST / with missing plan_id returns 422."""
        r = api.post(
            f"{BASE}/",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "price_id": _NULL_PRICE_ID,
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 422, r.text
        detail = r.json()["detail"]
        missing_fields = {err["loc"][-1] for err in detail if err["type"] == "missing"}
        assert "plan_id" in missing_fields

    def test_apply_discount_ids_duplicates_rejected(self, api):
        """POST /discounts/add rejects duplicate UUIDs in discount_ids."""
        dup_id = str(uuid4())
        r = api.post(
            f"{BASE}/discounts/add",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "discount_ids": [dup_id, dup_id],
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 422, r.text
        detail_text = r.json()["detail"][0]["msg"]
        assert "duplicate" in detail_text.lower()

    def test_add_discounts_empty_request_rejected(self, api):
        """POST /discounts/add with no discount_ids is a 422 (nothing to add)."""
        r = api.post(
            f"{BASE}/discounts/add",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "discount_ids": [],
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 422, r.text

    def test_charge_card_amount_must_be_positive(self, api):
        """POST /charge-card with amount_cents=0 returns 422."""
        r = api.post(
            f"{BASE}/charge-card",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "amount_cents": 0,
                "reason": "test",
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 422, r.text
        detail = r.json()["detail"]
        types = {err["type"] for err in detail}
        assert "greater_than" in types

    def test_charge_card_reason_must_be_non_empty(self, api):
        """POST /charge-card with empty reason returns 422."""
        r = api.post(
            f"{BASE}/charge-card",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "amount_cents": 1000,
                "reason": "",
                "idempotency_key": _IKEY,
            },
        )
        assert r.status_code == 422, r.text
        detail = r.json()["detail"]
        types = {err["type"] for err in detail}
        assert "string_too_short" in types

    def test_cancel_missing_query_params(self, api):
        """DELETE / missing required query params returns 422."""
        r = api.delete(f"{BASE}/")
        assert r.status_code == 422, r.text

    def test_cancel_preview_missing_member_id(self, api):
        """POST /cancel/preview missing member_id returns 422."""
        r = api.post(
            f"{BASE}/cancel/preview",
            params={"item_id": _NULL_ITEM_ID},
        )
        assert r.status_code == 422, r.text


# ---------------------------------------------------------------------------
# 404 — DB lookup, no Stripe work, authenticated
# ---------------------------------------------------------------------------


class TestNotFound:
    """Using valid auth but nonexistent IDs; expect 404 from DB lookup.

    These confirm:
    1. Auth + authorization pass (no 401/403).
    2. The DB query runs cleanly and returns a sensible 404 (no 500 from
       serialisation or SQL errors).
    3. Stripe is never reached (no credentials needed).
    """

    def test_cancel_nonexistent_item(self, api):
        """DELETE / with nonexistent item_id returns 404 with detail."""
        r = api.delete(
            f"{BASE}/",
            params={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code == 404, r.text
        assert "not found" in r.json()["detail"].lower()

    def test_freeze_no_billing_profile(self, api):
        """POST /freeze for a member with no billing profile returns 404.

        resolve_payer() looks up member_billing_profile; the seed has
        no billing profiles, so 404 is the correct behaviour.
        """
        r = api.post(
            f"{BASE}/freeze",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "freeze_months": 1,
                "idempotency_key": _idempotency_key(),
            },
        )
        # 404: no billing profile; 400 also acceptable (no Stripe customer)
        assert r.status_code in (400, 404), r.text
        assert r.status_code != 500, (
            f"Unexpected 500 on freeze — likely a serialisation or SQL bug; detail: {r.json()}"
        )

    def test_unfreeze_no_billing_profile(self, api):
        """POST /unfreeze for a member with no billing profile returns 404."""
        r = api.post(
            f"{BASE}/unfreeze",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code in (400, 404), r.text
        assert r.status_code != 500, (
            f"Unexpected 500 on unfreeze — likely a serialisation or SQL bug; detail: {r.json()}"
        )

    def test_start_nonexistent_plan(self, api):
        """POST / with nonexistent plan_id returns 404 with detail."""
        r = api.post(
            f"{BASE}/",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "plan_id": _NULL_PLAN_ID,
                "price_id": _NULL_PRICE_ID,
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code == 404, r.text
        detail = r.json()["detail"].lower()
        assert "plan" in detail or "price" in detail or "not found" in detail

    def test_update_price_nonexistent_item(self, api):
        """PUT /price with nonexistent item_id returns 404."""
        r = api.put(
            f"{BASE}/price",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code == 404, r.text
        assert "not found" in r.json()["detail"].lower()

    def test_add_discounts_nonexistent_item(self, api):
        """POST /discounts/add with nonexistent item_id returns 404.

        A non-empty preset list passes the schema's not-empty guard, so the
        membership lookup runs and returns 404.
        """
        r = api.post(
            f"{BASE}/discounts/add",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "discount_ids": [_NULL_PLAN_ID],
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code == 404, r.text
        assert "not found" in r.json()["detail"].lower()

    def test_mark_paid_cash_nonexistent_item(self, api):
        """POST /mark-paid-cash with nonexistent item_id returns 404."""
        r = api.post(
            f"{BASE}/mark-paid-cash",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code == 404, r.text
        assert "not found" in r.json()["detail"].lower()


# ---------------------------------------------------------------------------
# Preview paths — dry-run endpoints (no mutations, no real Stripe charges)
# ---------------------------------------------------------------------------


class TestPreviewPaths:
    """Dry-run / preview endpoints.

    Expected outcomes with the bare seed:
    - /preview (start)     → 404 (plan not found) or 502 (Stripe not wired)
    - /cancel/preview      → 404 (membership not found)
    - /discounts/add (preview=true) → 404 (membership not found)

    Any 500 indicates a real backend bug (serialisation, SQL, or unhandled
    exception that should have been a domain error).
    """

    SAFE_STATUSES = {400, 404, 502}  # expected: validation / not-found / Stripe-not-wired

    def test_preview_start_invalid_plan(self, api):
        """POST /preview with nonexistent plan returns 404 (plan lookup fails)."""
        r = api.post(
            f"{BASE}/preview",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "plan_id": _NULL_PLAN_ID,
                "price_id": _NULL_PRICE_ID,
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code in self.SAFE_STATUSES, (
            f"Expected 400/404/502 for preview with invalid plan; got {r.status_code}: {r.json()}"
        )
        assert r.status_code != 500, (
            f"500 on /preview — serialisation or unhandled exception bug: {r.json()}"
        )
        if r.status_code == 404:
            assert "not found" in r.json()["detail"].lower()

    def test_preview_cancel_nonexistent_item(self, api):
        """POST /cancel/preview with nonexistent item returns 404."""
        r = api.post(
            f"{BASE}/cancel/preview",
            params={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
            },
        )
        assert r.status_code == 404, r.text
        assert "not found" in r.json()["detail"].lower()

    def test_preview_discounts_nonexistent_item(self, api):
        """POST /discounts/add (preview=true) with a nonexistent item -> 404.

        The discount preview is the regular add path with ``preview=true``; a
        missing membership is a clean 404.
        """
        r = api.post(
            f"{BASE}/discounts/add",
            json={
                "item_id": _NULL_ITEM_ID,
                "member_id": MEMBER_ID,
                "discount_ids": [_NULL_PLAN_ID],
                "idempotency_key": _IKEY,
                "preview": True,
            },
        )
        assert r.status_code == 404, r.text
        assert "not found" in r.json()["detail"].lower()

    def test_preview_discounts_missing_member_id_rejected(self, api):
        """POST /discounts/add without member_id returns 422."""
        r = api.post(
            f"{BASE}/discounts/add",
            json={
                "item_id": _NULL_ITEM_ID,
                "discount_ids": [_NULL_PLAN_ID],
                "idempotency_key": _IKEY,
                "preview": True,
            },
        )
        assert r.status_code == 422, r.text

    def test_preview_start_response_is_none_or_object(self, api):
        """POST /preview that reaches Stripe-not-configured returns 502 not 500.

        If Stripe is configured the response is a DueNowVsRecurringPreview
        object or null. If Stripe is not configured the router wraps it in 502
        (PaymentsStripeError). A 500 means an unhandled exception leaked through.

        With the bare seed there is no plan so this will be 404. The assertion
        guards against any regression where the exception handler is bypassed.
        """
        r = api.post(
            f"{BASE}/preview",
            json={
                "member_id": MEMBER_ID,
                "gym_id": GYM_ID,
                "plan_id": _NULL_PLAN_ID,
                "price_id": _NULL_PRICE_ID,
                "idempotency_key": _idempotency_key(),
            },
        )
        assert r.status_code != 500, (
            f"500 on /preview indicates an unhandled exception — expected 404/400/502: {r.json()}"
        )
