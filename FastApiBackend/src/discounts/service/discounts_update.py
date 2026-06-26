"""Update a discount's identity (rename) and/or mint a new value version."""

from __future__ import annotations

import logging

from pydantic import BaseModel
from schema.gym_discount import DiscountType
from schema.immutable_columns import GYM_DISCOUNTS
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from src.discounts import SQL_DIR
from src.discounts.schema.discounts_schema import (
    DiscountResponse,
    DiscountUpdateRequest,
    DiscountValue,
)
from src.discounts.service.discounts_base import DiscountsBase
from src.shared.column_guard import validate_mutable_columns
from src.shared.sql_loader import load_sql

logger = logging.getLogger(__name__)


class DiscountsUpdate(DiscountsBase):
    """Edit a discount's identity (rename) and/or mint a new value version."""

    async def update_discount(
        self,
        request: DiscountUpdateRequest,
    ) -> DiscountResponse:
        """Rename identity and/or mint a new value version."""
        existing = await self._get_discount(request.discount_id, request.gym_id)

        # Custom discounts are one-shot; reject edits before the DB trigger fires.
        if existing["discount_type"] == DiscountType.custom.value:
            raise ValueError(
                f"Custom discount {request.discount_id} is one-shot and "
                f"cannot be edited (mint -> apply once -> archive)"
            )

        identity_changes = self._collect_changes(request.identity) if request.identity else {}
        if not identity_changes and request.value is None:
            return DiscountResponse.from_row(existing)

        if identity_changes:
            validate_mutable_columns(GYM_DISCOUNTS, set(identity_changes))

        result = dict(existing)
        async with self._db_pool.session() as session:
            if identity_changes:
                result.update(
                    await self._update_identity(
                        session,
                        request.discount_id,
                        request.gym_id,
                        identity_changes,
                    )
                )
            if request.value is not None:
                result.update(
                    await self._new_version(
                        session,
                        request.discount_id,
                        str(existing["gym_id"]),
                        request.value,
                    )
                )
            await session.commit()

        return DiscountResponse.from_row(result)

    # ── Private ────────────────────────────────────────────────

    @staticmethod
    def _collect_changes(model: BaseModel) -> dict[str, object]:
        """Return the non-None fields of an identity sub-model."""
        return {
            field: value
            for field in type(model).model_fields
            if (value := getattr(model, field)) is not None
        }

    @staticmethod
    async def _update_identity(
        session: AsyncSession,
        discount_id: object,
        gym_id: object,
        identity_changes: dict[str, object],
    ) -> dict:
        """Update the identity row (gym-scoped) with a dynamic SET clause."""
        set_clause = ", ".join(f"{col} = :{col}" for col in identity_changes)
        sql = load_sql(
            SQL_DIR / "discounts_update.sql",
            {"set_clause": set_clause},
        )
        params = {
            **identity_changes,
            "discount_id": str(discount_id),
            "gym_id": str(gym_id),
        }
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
        value: DiscountValue,
    ) -> dict:
        """Deactivate the active value version and insert a new one."""
        deactivate_sql = load_sql(SQL_DIR / "discount_values_deactivate.sql")
        await session.execute(
            text(deactivate_sql),
            {"discount_id": str(discount_id)},
        )

        insert_sql = load_sql(SQL_DIR / "discount_values_insert.sql")
        params = {
            "discount_id": str(discount_id),
            "gym_id": gym_id,
            "percentage_off": value.percentage_off,
            "dollar_off": value.dollar_off,
            "duration_amount": value.duration_amount,
            "duration_unit": (
                value.duration_unit.value if value.duration_unit is not None else None
            ),
            "end_date": value.end_date,
        }
        result = await session.execute(text(insert_sql), params)
        return dict(result.mappings().one())
