"""Update a regular discount.

A discount has a stable IDENTITY (gym_discounts: name + type) and a chain of
immutable VALUE versions (gym_discount_values). Editing splits accordingly:

* renaming updates the identity row in place;
* changing any value/lifetime field mints a NEW active version (deactivating the
  prior one) — value rows are a permanent paper trail.

Either way, edits affect only future applications — existing applied-discount
snapshots reference the old version and are frozen. There is no Stripe coupon to
swap (coupons are computed at sync) and no membership cascade.
"""

from __future__ import annotations

import logging

from pydantic import BaseModel
from schema.immutable_columns import GYM_DISCOUNTS
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.discounts import SQL_DIR
from src.discounts.schema.discounts_schema import (
    DiscountResponse,
    DiscountUpdateRequest,
    DiscountUpdateValues,
    _validate_lifetime,
)
from src.discounts.service.discounts.discounts_base import DiscountsBase
from src.shared.column_guard import validate_mutable_columns
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsUpdate(DiscountsBase):
    """Edit a discount's identity (rename) and/or mint a new value version."""

    async def update_discount(
        self,
        request: DiscountUpdateRequest,
    ) -> DiscountResponse:
        """Apply a partial update; the request shape picks the destination.

        `identity` renames the gym_discounts row in place; `values` mints a
        new active gym_discount_values version. Either may be omitted.

        Args:
            request: Discount update request (identity and/or values).

        Returns:
            The updated discount (identity + active value version).

        Raises:
            ValueError: If the discount is not found or the merged value
                state is invalid.
        """
        existing = await self._get_discount(request.discount_id)

        identity_changes = self._collect_changes(request.identity) if request.identity else {}
        value_changes = self._collect_changes(request.values) if request.values else {}
        if not identity_changes and not value_changes:
            return DiscountResponse(**existing)

        # The identity UPDATE is built dynamically from the changed columns,
        # so the guard does real work here (the value path is a static
        # full-column version INSERT and needs no guard).
        if identity_changes:
            validate_mutable_columns(GYM_DISCOUNTS, set(identity_changes))

        result = dict(existing)
        async with self._db_pool.session() as session:
            if identity_changes:
                result.update(
                    await self._update_identity(
                        session,
                        request.discount_id,
                        identity_changes,
                    )
                )
            if value_changes:
                result.update(
                    await self._new_version(
                        session,
                        request.discount_id,
                        str(existing["gym_id"]),
                        existing,
                        value_changes,
                    )
                )
            await session.commit()

        return DiscountResponse(**result)

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _collect_changes(model: BaseModel) -> dict[str, object]:
        """Extract the non-None fields of an update sub-model.

        Shared by `identity` and `values`: the sub-model's own field set is
        the source of truth, so adding a future editable column is just a
        model field — no change here.
        """
        return {
            field: value
            for field in type(model).model_fields
            if (value := getattr(model, field)) is not None
        }

    @staticmethod
    async def _update_identity(
        session: AsyncSession,
        discount_id: object,
        identity_changes: dict[str, object],
    ) -> dict:
        """Update the discount identity row (dynamic SET from changes).

        Column names come only from DiscountUpdateIdentity's fields (already
        guarded against GYM_DISCOUNTS), never raw client strings.
        """
        set_clause = ", ".join(f"{col} = :{col}" for col in identity_changes)
        sql = load_sql(
            SQL_DIR / "discounts_update.sql",
            {"set_clause": set_clause},
        )
        params = {**identity_changes, "discount_id": str(discount_id)}
        result = await session.execute(text(sql), params)
        row = result.mappings().fetchone()
        if not row:
            raise ValueError(f"Discount {discount_id} not found")
        return dict(row)

    async def _new_version(
        self,
        session: AsyncSession,
        discount_id: object,
        gym_id: str,
        existing: dict,
        value_changes: dict[str, object],
    ) -> dict:
        """Deactivate the active value version and insert a new one."""
        merged = {field: existing.get(field) for field in DiscountUpdateValues.model_fields}
        merged.update(value_changes)
        self._validate_merged_state(merged)

        deactivate_sql = load_sql(SQL_DIR / "discount_values_deactivate.sql")
        await session.execute(
            text(deactivate_sql),
            {"discount_id": str(discount_id)},
        )

        insert_sql = load_sql(SQL_DIR / "discount_values_insert.sql")
        params = {
            "discount_id": str(discount_id),
            "gym_id": gym_id,
            "percentage_off": merged["percentage_off"],
            "dollar_off": merged["dollar_off"],
            "discount_mode": str(merged["discount_mode"]),
            "duration_amount": merged["duration_amount"],
            "duration_unit": (
                str(merged["duration_unit"]) if merged["duration_unit"] is not None else None
            ),
            "end_date": merged["end_date"],
        }
        result = await session.execute(text(insert_sql), params)
        return dict(result.mappings().one())

    @staticmethod
    def _validate_merged_state(merged: dict) -> None:
        """Validate the merged value state after applying changes.

        Raises:
            ValueError: If the merged value violates constraints.
        """
        has_pct = merged.get("percentage_off") is not None
        has_amt = merged.get("dollar_off") is not None
        if has_pct == has_amt:
            raise ValueError(
                "Exactly one of percentage_off or dollar_off must be set",
            )

        _validate_lifetime(
            duration_amount=merged.get("duration_amount"),
            duration_unit=merged.get("duration_unit"),
            end_date=merged.get("end_date"),
        )
