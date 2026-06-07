"""Version-tolerant readers for Stripe invoice / line payloads.

Stripe's 2026 "dahlia" API generation moved several invoice fields under a
typed ``parent`` discriminator:

- A line's subscription item id moved from the flat ``line["subscription_item"]``
  to ``line["parent"]["subscription_item_details"]["subscription_item"]``.
- The invoice's subscription id moved from ``invoice["subscription"]`` to
  ``invoice["parent"]["subscription_details"]["subscription"]``, and the
  subscription's metadata (member_id / gym_id / ``crm_paid_with_cash``) now
  surfaces at ``invoice["parent"]["subscription_details"]["metadata"]`` instead
  of being copied onto the invoice root.

These pure readers centralize that knowledge in one place so the webhook
handlers don't repeat the nesting. Each reads the new nested location first and
falls back to the old flat field, so the handlers stay correct whether an
endpoint delivers the new shape (default) or an older pinned API version.
"""

from __future__ import annotations

from typing import Any


def line_subscription_item(line: dict[str, Any]) -> str | None:
    """Return a line's Stripe subscription item id, or ``None``.

    New nested location first, old flat field as fallback.
    """
    parent = line.get("parent")
    if isinstance(parent, dict):
        details = parent.get("subscription_item_details")
        if isinstance(details, dict):
            item_id = details.get("subscription_item")
            if item_id:
                return item_id
    return line.get("subscription_item")


def invoice_subscription_id(invoice: dict[str, Any]) -> str | None:
    """Return an invoice's Stripe subscription id, or ``None``.

    New nested location first, old flat field as fallback.
    """
    parent = invoice.get("parent")
    if isinstance(parent, dict):
        details = parent.get("subscription_details")
        if isinstance(details, dict):
            sub_id = details.get("subscription")
            if sub_id:
                return sub_id
    return invoice.get("subscription")


def invoice_metadata(invoice: dict[str, Any]) -> dict[str, Any]:
    """Return the invoice's effective metadata for flow-control reads.

    One-time invoices carry their metadata on the invoice root; subscription
    invoices carry it under ``parent.subscription_details.metadata``. Merge both
    (subscription-details metadata layered on top) so ``crm_one_time_payment`` /
    ``crm_paid_with_cash`` / ``member_id`` resolve regardless of the source.
    """
    merged: dict[str, Any] = {}
    root = invoice.get("metadata")
    if isinstance(root, dict):
        merged.update(root)
    parent = invoice.get("parent")
    if isinstance(parent, dict):
        details = parent.get("subscription_details")
        if isinstance(details, dict):
            sub_metadata = details.get("metadata")
            if isinstance(sub_metadata, dict):
                merged.update(sub_metadata)
    return merged
