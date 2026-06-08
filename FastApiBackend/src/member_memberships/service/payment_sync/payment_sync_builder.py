"""Builder service: produce the desired ``SyncParams`` from the DB.

Reads the family's active recurring memberships (each carrying its discounts),
groups them into consolidated lines by price, delegates discount-coupon
resolution to ``PaymentSyncDiscounts``, and assembles the monthly subscription
bucket — the full desired state the reconciler converges Stripe onto. This
service owns the DB read + grouping + bucket assembly; the discount *math* lives
in ``PaymentSyncDiscounts``.
"""

from collections import defaultdict
from uuid import UUID

from schema.membership_plan import DurationUnit

import src.shared.db_schema_path  # noqa: F401
from src.member_memberships.schema.payment_sync_schema import (
    ActiveMembershipRow,
    IntervalBucket,
    SyncParams,
)
from src.member_memberships.service.payment_sync.payment_sync_discounts import (
    PaymentSyncDiscounts,
)
from src.member_memberships.service.payment_sync.payment_sync_queries import (
    PaymentSyncQueries,
)
from src.payments.schema.payments_members_schema import (
    PaymentsSubscriptionDesiredItem,
    SubscriptionItemDiscount,
)
from src.shared.billing_parent import ParentProfile
from src.shared.database import DirectDatabasePool
from src.shared.gym_timezone import gym_today


class PaymentSyncBuilder:
    """Builds the desired ``SyncParams`` (bucket + resolved coupons) from the DB.

    Pure desired-state derivation: read the active memberships and their
    discounts, group by price, resolve each line's coupons via
    ``PaymentSyncDiscounts``, and assemble the bucket. No DB writes — preview and
    the real path share it, so preview reflects discounts.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        discounts: PaymentSyncDiscounts,
    ) -> None:
        self._queries = PaymentSyncQueries(db_pool)
        self._discounts = discounts

    async def build_sync_params(
        self,
        parent: ParentProfile,
        stripe_account_id: str,
        preview: bool = False,
    ) -> SyncParams:
        """Read the DB, resolve discounts, and assemble the desired bucket.

        ``preview`` is threaded into the read so a dry run sees the staged
        ``preview_add`` rows (and drops ``preview_remove``) while the real path
        sees neither — the only difference between the two builds.

        Derives the desired subscription state entirely from the DB — the active
        recurring memberships, each carrying its applied discounts (cancelled
        rows excluded by the read) — never from imperative add/cancel lists.
        Groups the memberships into consolidated lines by ``price_id`` and hands
        them to ``PaymentSyncDiscounts``, which resolves each line's coupons
        (find-or-create, percent→dollar) and returns the per-price coupon lists
        plus the ``applied_discount_id → coupon_id`` links; the bucket items
        carry the coupons. Shared by the real (``update_payments_recurring``) and
        preview sync paths — so preview reflects discounts. Performs **no DB
        writes** (coupon find-or-create is an idempotent gym-wide Stripe op; the
        link writeback is the orchestrator's, real path only). The paying parent
        + gym Stripe account are resolved upstream and passed in.
        """
        today = gym_today(parent.timezone)
        family_ids = await self._queries.get_family_ids(parent)
        memberships = await self._queries.get_active_memberships(
            family_ids,
            today,
            preview,
        )
        groups = self._group_by_price(memberships)

        resolved = await self._discounts.resolve(groups, stripe_account_id)
        bucket = self._build_bucket(
            groups,
            resolved.coupons_by_price,
            parent.stripe_sub_id_month,
        )

        return SyncParams(
            bucket=bucket,
            parent=parent,
            stripe_account_id=stripe_account_id,
            coupon_links=resolved.links,
            membership_post_discount_amounts=resolved.membership_amounts,
            memberships=memberships,
        )

    @staticmethod
    def _group_by_price(
        memberships: list[ActiveMembershipRow],
    ) -> dict[UUID, list[ActiveMembershipRow]]:
        """Group the active memberships into consolidated lines by price.

        All recurring plans are monthly (DB constraint
        recurring_must_be_monthly), so there is exactly one billing interval; the
        only consolidation axis is the price. Each ``price_id`` becomes one
        subscription line whose quantity is the number of memberships on it.
        """
        groups: dict[UUID, list[ActiveMembershipRow]] = defaultdict(list)
        for membership in memberships:
            groups[membership.price_id].append(membership)
        return dict(groups)

    @staticmethod
    def _build_bucket(
        groups: dict[UUID, list[ActiveMembershipRow]],
        coupons_by_price: dict[UUID, list[SubscriptionItemDiscount]],
        existing_sub_id: str | None,
    ) -> IntervalBucket:
        """Build the monthly subscription bucket from the grouped memberships.

        One desired item per price group: quantity = number of memberships on the
        line, discounts = the coupons the discount service resolved for that price
        (empty when the line has none). All recurring plans are monthly, so there
        is exactly one bucket.
        """
        items: list[PaymentsSubscriptionDesiredItem] = []
        for price_id, memberships in groups.items():
            first = memberships[0]
            # Use the existing line's id if any row on this price already has
            # one (UPDATE that line); a price group that is entirely new
            # (all pending, stripe_item_id NULL) gets None → Stripe CREATE.
            stripe_item_id = next(
                (m.stripe_item_id for m in memberships if m.stripe_item_id),
                None,
            )
            items.append(
                PaymentsSubscriptionDesiredItem(
                    stripe_price_id=first.stripe_price_id,
                    stripe_item_id=stripe_item_id,
                    quantity=len(memberships),
                    discounts=coupons_by_price.get(price_id, []),
                )
            )
        return IntervalBucket(
            interval=DurationUnit.month,
            items=items,
            existing_sub_id=existing_sub_id,
        )
