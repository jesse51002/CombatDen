"""Membership plan CRUD operations (facade).

Delegates to focused sub-services while preserving
the public API and constructor signature.
"""

from __future__ import annotations

from uuid import UUID

from fastapi import BackgroundTasks

from src.discounts.service.discounts.discounts_service import (
    DiscountsService,
)
from src.member_memberships.service.payment_sync.payment_sync_service import (
    PaymentSyncService,
)
from src.membership_plans.membership_plans_schemas import (
    MembershipPlanCreateRequest,
    MembershipPlanPriceRequest,
    MembershipPlanPriceResponse,
    MembershipPlanPriceWithCount,
    MembershipPlanResponse,
    MembershipPlanUpdateRequest,
)
from src.membership_plans.service.plans.membership_plans_create import (
    MembershipPlansCreate,
)
from src.membership_plans.service.plans.membership_plans_delete import (
    MembershipPlansDelete,
)
from src.membership_plans.service.plans.membership_plans_price import (
    MembershipPlansPrice,
)
from src.membership_plans.service.plans.membership_plans_read import (
    MembershipPlansRead,
)
from src.membership_plans.service.plans.membership_plans_update import (
    MembershipPlansUpdate,
)
from src.payments.service.payments_stripe_membership_service import (
    PaymentsStripeMembershipService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)
from src.shared.database import DirectDatabasePool
from src.shared.gym_stripe_service import GymStripeService


class MembershipPlansService:
    """Membership plan CRUD operations (facade).

    Delegates to focused sub-services for create, update,
    delete, read, and price operations.
    """

    def __init__(
        self,
        db_pool: DirectDatabasePool,
        gym_stripe_service: GymStripeService,
        stripe_membership_service: PaymentsStripeMembershipService,
        stripe_price_service: PaymentsStripePriceService,
        payment_sync_service: PaymentSyncService,
        discounts_service: DiscountsService,
    ) -> None:
        deps = (
            db_pool,
            gym_stripe_service,
            stripe_membership_service,
            stripe_price_service,
            discounts_service,
        )
        self._create = MembershipPlansCreate(*deps)
        self._update = MembershipPlansUpdate(*deps)
        self._delete = MembershipPlansDelete(*deps)
        self._read = MembershipPlansRead(*deps)
        self._price = MembershipPlansPrice(
            *deps,
            payment_sync_service=payment_sync_service,
        )

    # ── Create ─────────────────────────────────────────────────

    async def create_plan(
        self,
        request: MembershipPlanCreateRequest,
    ) -> MembershipPlanResponse:
        """Create a membership plan in CRM and Stripe."""
        return await self._create.create_plan(request)

    # ── Update ─────────────────────────────────────────────────

    async def update_plan(
        self,
        request: MembershipPlanUpdateRequest,
    ) -> MembershipPlanResponse:
        """Update a membership plan in CRM and Stripe."""
        return await self._update.update_plan(request)

    # ── Delete ─────────────────────────────────────────────────

    async def delete_plan(
        self,
        plan_id: UUID,
        gym_id: UUID,
    ) -> None:
        """Soft-delete a membership plan."""
        await self._delete.delete_plan(plan_id, gym_id)

    # ── Read ───────────────────────────────────────────────────

    async def list_plans(
        self,
        gym_id: UUID,
    ) -> list[MembershipPlanResponse]:
        """List all non-deleted plans for a gym."""
        return await self._read.list_plans(gym_id)

    async def get_plan(
        self,
        plan_id: UUID,
        gym_id: UUID,
    ) -> MembershipPlanResponse:
        """Get a single plan with its active price."""
        return await self._read.get_plan(plan_id, gym_id)

    async def list_prices(
        self,
        plan_id: UUID,
        gym_id: UUID,
    ) -> list[MembershipPlanPriceWithCount]:
        """List a plan's price versions with per-price member counts."""
        return await self._read.list_prices(plan_id, gym_id)

    # ── Price ──────────────────────────────────────────────────

    async def set_price(
        self,
        request: MembershipPlanPriceRequest,
    ) -> MembershipPlanPriceResponse:
        """Set / update the active price on a plan."""
        return await self._price.set_price(request)

    # ── Migrate ────────────────────────────────────────────────

    async def migrate_all_members(
        self,
        plan_id: UUID,
        gym_id: UUID,
        background_tasks: BackgroundTasks,
    ) -> None:
        """Migrate all active members on a plan to the current price."""
        await self._price.migrate_all_members(
            plan_id,
            gym_id,
            background_tasks,
        )

    async def migrate_members(
        self,
        plan_id: UUID,
        gym_id: UUID,
        member_ids: list[UUID],
        background_tasks: BackgroundTasks,
    ) -> None:
        """Migrate specific members to the current active price."""
        await self._price.migrate_members(
            plan_id,
            gym_id,
            member_ids,
            background_tasks,
        )
