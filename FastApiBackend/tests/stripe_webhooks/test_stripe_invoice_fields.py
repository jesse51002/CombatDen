"""Unit tests for the dahlia-aware Stripe invoice field readers.

Each reader must read the new nested ``parent`` location first and fall back to
the old flat field, so the webhook handlers stay correct whether an endpoint
delivers the 2026 "dahlia" shape (default) or an older pinned API version.
"""

from src.stripe_webhooks.service.stripe_invoice_fields import (
    invoice_metadata,
    invoice_subscription_id,
    line_subscription_item,
)

# ── line_subscription_item ──────────────────────────────────────────


def test_line_subscription_item_reads_new_nested_shape() -> None:
    line = {
        "id": "il_1",
        "parent": {
            "type": "subscription_item_details",
            "subscription_item_details": {
                "subscription": "sub_1",
                "subscription_item": "si_new",
            },
        },
    }

    assert line_subscription_item(line) == "si_new"


def test_line_subscription_item_falls_back_to_old_flat_shape() -> None:
    line = {"id": "il_1", "subscription_item": "si_old"}

    assert line_subscription_item(line) == "si_old"


def test_line_subscription_item_prefers_nested_over_flat() -> None:
    line = {
        "id": "il_1",
        "subscription_item": "si_old",
        "parent": {
            "subscription_item_details": {"subscription_item": "si_new"},
        },
    }

    assert line_subscription_item(line) == "si_new"


def test_line_subscription_item_none_for_one_off_item_line() -> None:
    # An invoice-item line (one-off) has no subscription item in either shape.
    line = {
        "id": "il_1",
        "parent": {
            "type": "invoice_item_details",
            "invoice_item_details": {"invoice_item": "ii_1"},
        },
    }

    assert line_subscription_item(line) is None


def test_line_subscription_item_none_when_absent() -> None:
    assert line_subscription_item({"id": "il_1"}) is None


# ── invoice_subscription_id ─────────────────────────────────────────


def test_invoice_subscription_id_reads_new_nested_shape() -> None:
    invoice = {
        "id": "in_1",
        "parent": {
            "type": "subscription_details",
            "subscription_details": {"subscription": "sub_new"},
        },
    }

    assert invoice_subscription_id(invoice) == "sub_new"


def test_invoice_subscription_id_falls_back_to_old_flat_shape() -> None:
    assert invoice_subscription_id({"id": "in_1", "subscription": "sub_old"}) == "sub_old"


def test_invoice_subscription_id_none_for_one_time_invoice() -> None:
    invoice = {"id": "in_1", "parent": {"type": "quote_details"}}

    assert invoice_subscription_id(invoice) is None


# ── invoice_metadata ────────────────────────────────────────────────


def test_invoice_metadata_reads_root_for_one_time_invoice() -> None:
    invoice = {
        "id": "in_1",
        "metadata": {"crm_one_time_payment": "true", "member_id": "m1"},
    }

    md = invoice_metadata(invoice)
    assert md["crm_one_time_payment"] == "true"
    assert md["member_id"] == "m1"


def test_invoice_metadata_reads_subscription_details_for_sub_invoice() -> None:
    invoice = {
        "id": "in_1",
        "metadata": {},
        "parent": {
            "subscription_details": {
                "subscription": "sub_1",
                "metadata": {
                    "member_id": "m2",
                    "gym_id": "g2",
                    "crm_paid_with_cash": "false",
                },
            },
        },
    }

    md = invoice_metadata(invoice)
    assert md["member_id"] == "m2"
    assert md["gym_id"] == "g2"
    assert md["crm_paid_with_cash"] == "false"


def test_invoice_metadata_merges_both_sources() -> None:
    invoice = {
        "id": "in_1",
        "metadata": {"root_only": "r"},
        "parent": {"subscription_details": {"metadata": {"sub_only": "s"}}},
    }

    md = invoice_metadata(invoice)
    assert md == {"root_only": "r", "sub_only": "s"}


def test_invoice_metadata_empty_when_absent() -> None:
    assert invoice_metadata({"id": "in_1"}) == {}
