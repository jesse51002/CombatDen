from dependency_injector import containers, providers

from src.classes.service.classes_checkin_service import ClassesCheckinService
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
from src.classes.service.classes_streak_service import ClassesStreakService
from src.core.config import settings
from src.members.service.member_details.member_details_price_recalc import (
    MemberDetailsPriceRecalc,
)
from src.members.service.member_details_service import (
    MemberService,
)
from src.members.service.members_crm_members_list_service import (
    CrmMembersListService,
)
from src.members.service.members_crm_total_counts_service import (
    CrmTotalCountsService,
)
from src.payments.service.payments_stripe_client import PaymentsStripeClient
from src.payments.service.payments_stripe_discount_service import (
    PaymentsStripeDiscountService,
)
from src.payments.service.payments_stripe_members_service import (
    PaymentsStripeMembersService,
)
from src.payments.service.payments_stripe_membership_service import (
    PaymentsStripeMembershipService,
)
from src.payments.service.payments_stripe_payment_service import (
    PaymentsStripePaymentService,
)
from src.payments.service.payments_stripe_price_service import (
    PaymentsStripePriceService,
)
from src.payments.service.subscription import (
    PaymentsStripeSubscriptionService,
)
from src.shared.auth import Auth
from src.shared.database import (
    DirectDatabasePool,
    SupabaseClient,
)
from src.shared.membership_pricing.membership_pricing_service import (
    MembershipPricingService,
)


class DependencyInjector(containers.DeclarativeContainer):
    """Application dependency injection container.

    Add new domain modules to wiring_config.modules
    when they use @inject with Provide[...].
    """

    wiring_config = containers.WiringConfiguration(
        modules=[
            "src.main",
            "src.members.members_router",
            "src.classes.classes_router",
        ],
    )

    db_pool = providers.Singleton(DirectDatabasePool)
    supabase = providers.Singleton(SupabaseClient)
    auth = providers.Singleton(Auth, supabase=supabase)
    membership_pricing = providers.Singleton(MembershipPricingService)
    cycle_counts_service = providers.Factory(ClassesCycleCountsService, db_pool=db_pool)
    streak_service = providers.Factory(ClassesStreakService, db_pool=db_pool)
    member_service = providers.Factory(
        MemberService,
        db_pool=db_pool,
        pricing=membership_pricing,
        cycle_counts_service=cycle_counts_service,
        streak_service=streak_service,
    )
    price_recalc = providers.Factory(
        MemberDetailsPriceRecalc,
        db_pool=db_pool,
        pricing=membership_pricing,
    )
    crm_members_list_service = providers.Factory(CrmMembersListService, db_pool=db_pool)
    crm_total_counts_service = providers.Factory(CrmTotalCountsService, db_pool=db_pool)
    checkin_service = providers.Factory(
        ClassesCheckinService,
        db_pool=db_pool,
        cycle_counts_service=cycle_counts_service,
    )

    # ── Payments (Stripe) ────────────────────────────────────────
    stripe_client = providers.Singleton(
        PaymentsStripeClient,
        secret_key=settings.stripe_secret_key,
    )
    payments_price_service = providers.Factory(
        PaymentsStripePriceService,
        stripe_client=stripe_client,
    )
    payments_membership_service = providers.Factory(
        PaymentsStripeMembershipService,
        stripe_client=stripe_client,
        price_service=payments_price_service,
    )
    payments_discount_service = providers.Factory(
        PaymentsStripeDiscountService,
        stripe_client=stripe_client,
    )
    payments_members_service = providers.Factory(
        PaymentsStripeMembersService,
        stripe_client=stripe_client,
    )
    payments_subscription_service = providers.Factory(
        PaymentsStripeSubscriptionService,
        stripe_client=stripe_client,
        members_service=payments_members_service,
        price_service=payments_price_service,
        discount_service=payments_discount_service,
    )
    payments_payment_service = providers.Factory(
        PaymentsStripePaymentService,
        stripe_client=stripe_client,
        members_service=payments_members_service,
        price_service=payments_price_service,
    )
