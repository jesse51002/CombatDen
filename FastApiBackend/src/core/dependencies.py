from dependency_injector import containers, providers

from src.members.members_service import MemberService
from src.shared.auth import Auth
from src.shared.database import DirectDatabasePool, SupabaseClient


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
    member_service = providers.Factory(MemberService)
