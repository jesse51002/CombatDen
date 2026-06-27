"""Membership plan CRUD operations (facade).

Delegates to focused sub-services while preserving
the public API and constructor signature.
"""

from __future__ import annotations

from uuid import UUID

from src.payments.service.payments_stripe_membership_service import (
    PaymentsStripeMembershipService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)
from src.plans.plans_schema import (
    MembershipPlanCreateRequest,
    MembershipPlanPriceRequest,
    MembershipPlanPriceResponse,
    MembershipPlanPriceWithCount,
    MembershipPlanResponse,
    MembershipPlanUpdateRequest,
)
from src.plans.service.plans_create import (
    MembershipPlansCreate,
)
from src.plans.service.plans_delete import (
    MembershipPlansDelete,
)
from src.plans.service.plans_price import (
    MembershipPlansPrice,
)
from src.plans.service.plans_read import (
    MembershipPlansRead,
)
from src.plans.service.plans_update import (
    MembershipPlansUpdate,
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
    ) -> None:
        deps = (
            db_pool,
            gym_stripe_service,
            stripe_membership_service,
            stripe_price_service,
        )
        self._create = MembershipPlansCreate(*deps)
        self._update = MembershipPlansUpdate(*deps)
        self._delete = MembershipPlansDelete(*deps)
        self._read = MembershipPlansRead(*deps)
        self._price = MembershipPlansPrice(*deps)

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
