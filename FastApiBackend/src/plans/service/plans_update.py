"""Update a membership plan in CRM and Stripe."""

from __future__ import annotations

import json
import logging
from typing import TYPE_CHECKING
from uuid import UUID

from schema.immutable_columns import MEMBERSHIP_PLANS
from schema.membership_plan import DurationUnit, PlanType
from sqlalchemy import text

import src.shared.db_schema_path  # noqa: F401
from src.payments.payments_exceptions import PaymentsResourceNotFoundError
from src.payments.schema.metadata.stripe_product_metadata import (
    StripeProductMetadata,
)
from src.payments.schema.payments_enums import StripeResourceType
from src.payments.schema.payments_membership_schema import (
    PaymentsMembershipCreateRequest,
    PaymentsMembershipPriceItem,
    PaymentsMembershipUpdateRequest,
)
from src.plans import SQL_DIR
from src.plans.plans_schema import (
    MembershipPlanResponse,
    MembershipPlanUpdateData,
    MembershipPlanUpdateRequest,
    _check_plan_constraints,
)
from src.plans.service.plans_base import (
    MembershipPlansBase,
)
from src.shared.column_guard import validate_mutable_columns
from src.shared.sql_loader import load_sql

if TYPE_CHECKING:
    pass

logger = logging.getLogger(__name__)

# jsonb columns are bound as JSON text + cast to jsonb in the SET clause.
_JSONB_COLUMNS = frozenset({"waiver_ids"})


class MembershipPlansUpdate(MembershipPlansBase):
    """Update a membership plan in CRM and Stripe."""

    async def update_plan(
        self,
        request: MembershipPlanUpdateRequest,
    ) -> MembershipPlanResponse:
        """Update plan metadata in Stripe then CRM (non-None fields only)."""
        existing = await self._get_plan(request.plan_id, request.gym_id)

        changes = self._collect_changes(request.data)
        if not changes:
            return self._build_plan_response(
                existing,
                active_price=self._extract_active_price(existing),
            )

        validate_mutable_columns(MEMBERSHIP_PLANS, set(changes.keys()))
        if request.data.waiver_ids is not None:
            await self._validate_waiver_ids(
                request.gym_id,
                request.data.waiver_ids,
            )

        merged = {**existing, **changes}
        self._validate_merged_state(merged)

        stripe_account_id = await self._gym_stripe.get_stripe_account_id(
            request.gym_id,
        )

        # ── Stripe first ──────────────────────────────────────
        stripe_product_id = existing["stripe_product_id"]
        product_recreated = False
        if stripe_product_id:
            new_stripe_product_id = await self._update_or_recreate_product(
                stripe_product_id=stripe_product_id,
                merged=merged,
                stripe_account_id=stripe_account_id,
                plan_id=request.plan_id,
                gym_id=request.gym_id,
            )
            product_recreated = new_stripe_product_id != stripe_product_id
            stripe_product_id = new_stripe_product_id

        # ── CRM update ───────────────────────────────────────
        # jsonb uses CAST(:col AS JSONB); colon-colon cast breaks asyncpg.
        set_clause = ", ".join(
            f"{col} = CAST(:{col} AS JSONB)"
            if col in _JSONB_COLUMNS
            else f"{col} = :{col}"
            for col in changes
        )
        update_sql = load_sql(
            SQL_DIR / "membership_plans_update.sql",
            {"set_clause": set_clause},
        )

        params: dict[str, object] = {
            "plan_id": str(request.plan_id),
            "gym_id": str(request.gym_id),
        }
        for col, val in changes.items():
            params[col] = self._bind_value(col, val)

        async with self._db_pool.session() as session:
            result = await session.execute(text(update_sql), params)
            row = result.mappings().fetchone()
            if not row:
                raise ValueError(f"Plan {request.plan_id} not found")
            # Persist the new product id if the old one was gone and recreated.
            if product_recreated:
                set_product_id_sql = load_sql(
                    SQL_DIR / "membership_plans_set_stripe_product_id.sql",
                )
                await session.execute(
                    text(set_product_id_sql),
                    {
                        "plan_id": str(request.plan_id),
                        "gym_id": str(request.gym_id),
                        "stripe_product_id": stripe_product_id,
                    },
                )
            await session.commit()

        # Re-fetch to get the joined price columns
        full_plan = await self._get_plan(request.plan_id, request.gym_id)
        return self._build_plan_response(
            full_plan,
            active_price=self._extract_active_price(full_plan),
        )

    # ── Private ────────────────────────────────────────────────

    async def _update_or_recreate_product(
        self,
        stripe_product_id: str,
        merged: dict,
        stripe_account_id: str,
        *,
        plan_id: UUID,
        gym_id: UUID,
    ) -> str:
        """Update the Stripe product, recreating if not found.

        Returns:
            The (possibly new) stripe_product_id.
        """
        metadata = StripeProductMetadata(plan_id=plan_id, gym_id=gym_id)
        try:
            await self._stripe_memberships.update_membership(
                PaymentsMembershipUpdateRequest(
                    stripe_product_id=stripe_product_id,
                    plan_name=merged["plan_name"],
                    prices=[
                        PaymentsMembershipPriceItem(
                            stripe_price_id=(merged.get("price_stripe_price_id")),
                            active=True,
                            is_default=True,
                        ),
                    ]
                    if merged.get("price_stripe_price_id")
                    else [
                        PaymentsMembershipPriceItem(
                            unit_amount=0,
                            plan_type=PlanType(merged["plan_type"]),
                            recurring_interval=DurationUnit.month,
                            recurring_interval_count=1,
                            is_default=True,
                        ),
                    ],
                    metadata=metadata,
                ),
                stripe_account_id,
            )
            return stripe_product_id
        except PaymentsResourceNotFoundError as exc:
            if exc.resource_type != StripeResourceType.product:
                raise
            logger.warning(
                "Stripe product %s not found — recreating",
                stripe_product_id,
            )
            resp = await self._stripe_memberships.create_membership(
                PaymentsMembershipCreateRequest(
                    plan_name=merged["plan_name"],
                    prices=[
                        PaymentsMembershipPriceItem(
                            unit_amount=0,
                            plan_type=PlanType(merged["plan_type"]),
                            recurring_interval=DurationUnit.month,
                            recurring_interval_count=1,
                            is_default=True,
                        ),
                    ],
                    metadata=metadata,
                ),
                stripe_account_id,
            )
            return resp.stripe_product_id

    @staticmethod
    def _collect_changes(
        data: MembershipPlanUpdateData,
    ) -> dict[str, object]:
        """Extract non-None mutable fields from the update data."""
        changes: dict[str, object] = {}
        for field in MembershipPlanUpdateData.model_fields:
            value = getattr(data, field)
            if value is not None:
                changes[field] = value
        return changes

    @staticmethod
    def _bind_value(col: str, val: object) -> object:
        """Serialize a value for SQL binding (jsonb→JSON text, enum→value)."""
        if col == "waiver_ids":
            return json.dumps([str(u) for u in val])  # type: ignore[union-attr]
        return val.value if hasattr(val, "value") else val

    @staticmethod
    def _validate_merged_state(merged: dict) -> None:
        """Validate merged plan state against DB CHECK constraints."""
        plan_type = PlanType(merged["plan_type"])
        duration_unit = (
            DurationUnit(merged["duration_unit"]) if merged.get("duration_unit") else None
        )

        _check_plan_constraints(
            plan_type=plan_type,
            duration_amount=merged.get("duration_amount"),
            duration_unit=duration_unit,
            class_count=merged.get("class_count"),
        )
