from dependency_injector import containers, providers

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


class DependencyInjector(containers.DeclarativeContainer):
    """Application dependency injection container.

    Add new domain modules to wiring_config.modules
    when they use @inject with Provide[...].
    """

    wiring_config = containers.WiringConfiguration(
        modules=[
            "src.main",
            "src.members.members_router",
        ],
    )

    db_pool = providers.Singleton(DirectDatabasePool)
    supabase = providers.Singleton(SupabaseClient)
    auth = providers.Singleton(Auth, supabase=supabase)
    member_service = providers.Factory(MemberService, db_pool=db_pool)
    price_recalc = providers.Factory(MemberDetailsPriceRecalc, db_pool=db_pool)
    crm_members_list_service = providers.Factory(CrmMembersListService, db_pool=db_pool)
    crm_total_counts_service = providers.Factory(CrmTotalCountsService, db_pool=db_pool)
