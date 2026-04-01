import random
import uuid
from typing import Optional

from faker import Faker

from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_datetime

fake = Faker()


def generate(
    gym_id: uuid.UUID,
    crm_user_id: Optional[uuid.UUID] = None,
    user_id: Optional[str] = None,
) -> UserGymProfileCreate:
    return UserGymProfileCreate(
        crm_user_id=crm_user_id or uuid.uuid4(),
        user_id=user_id,
        gym_id=gym_id,
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        email=fake.email(),
        phone=fake.phone_number(),
        address=fake.address().replace("\n", ", "),
        current_rank=random.choice([None, 1, 2, 3, 4, 5]),
        points_balance=random.randint(0, 500),
        last_class=random_past_datetime(30) if random.random() > 0.3 else None,
        emergency_contact_name=fake.name(),
        emergency_contact_phone=fake.phone_number(),
        emergency_contact_email=fake.email(),
    )
