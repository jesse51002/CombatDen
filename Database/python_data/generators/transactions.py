import random
import uuid

from schema.membership_plan import MembershipPlanCreate
from schema.membership_plan_price import MembershipPlanPriceCreate
from schema.user_gym_transaction import UserGymTransactionCreate
from utils import random_past_datetime

TRANSACTION_TYPES = ["membership_payment", "reward_purchase", "merchandise"]


def generate(
    crm_user_id: uuid.UUID,
    gym_id: uuid.UUID,
    plans: list[MembershipPlanCreate],
    prices: dict[uuid.UUID, MembershipPlanPriceCreate],
    count: int,
) -> list[UserGymTransactionCreate]:
    transactions = []
    for _ in range(count):
        item_type = random.choice(TRANSACTION_TYPES)
        if item_type == "membership_payment":
            plan = random.choice(plans)
            item_id = plan.plan_id
            amount = prices[plan.plan_id].price
        else:
            item_id = uuid.uuid4()
            amount = random.randint(500, 10000)

        transactions.append(
            UserGymTransactionCreate(
                crm_user_id=crm_user_id,
                gym_id=gym_id,
                item_id=item_id,
                amount_paid=amount,
                item_type=item_type,
                time=random_past_datetime(90),
            )
        )
    return transactions
