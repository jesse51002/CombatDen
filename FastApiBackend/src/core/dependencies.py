from dependency_injector import containers, providers

from src.classes.service.classes_checkin_service import ClassesCheckinService
from src.classes.service.classes_cycle_counts_service import (
    ClassesCycleCountsService,
)
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
    member_service = providers.Factory(
        MemberService,
        db_pool=db_pool,
        pricing=membership_pricing,
        cycle_counts_service=cycle_counts_service,
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
