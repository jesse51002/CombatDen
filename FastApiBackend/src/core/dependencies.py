from dependency_injector import containers, providers

from src.classes.service.classes_checkin_service import ClassesCheckinService
from src.classes.service.classes_streak_service import ClassesStreakService
from src.gyms.service.gyms_service import GymsService
from src.members.service.members_service import MembersService
from src.ranks.service.ranks_service import RanksService
from src.rewards.service.rewards_redemption_service import (
    RewardsRedemptionService,
)
from src.rewards.service.rewards_service import RewardsService
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
            "src.classes.classes_router",
            "src.gyms.gyms_router",
            "src.members.members_router",
            "src.ranks.ranks_router",
            "src.rewards.rewards_router",
        ],
    )

    db_pool = providers.Singleton(DirectDatabasePool)
    supabase = providers.Singleton(SupabaseClient)
    auth = providers.Singleton(Auth, supabase=supabase)

    gyms_service = providers.Factory(GymsService, db_pool=db_pool)
    members_service = providers.Factory(MembersService, db_pool=db_pool)

    streak_service = providers.Factory(ClassesStreakService, db_pool=db_pool)
    checkin_service = providers.Factory(ClassesCheckinService, db_pool=db_pool)

    rewards_service = providers.Factory(RewardsService, db_pool=db_pool)
    rewards_redemption_service = providers.Factory(RewardsRedemptionService, db_pool=db_pool)

    ranks_service = providers.Factory(RanksService, db_pool=db_pool)
