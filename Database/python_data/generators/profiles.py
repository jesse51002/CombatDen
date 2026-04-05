import random
import uuid
from pathlib import Path
from typing import Optional

import yaml
from faker import Faker

from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_datetime

_images_path = Path(__file__).parent / "sample_images.yaml"
with open(_images_path) as f:
    _sample_images: list[str] = yaml.safe_load(f)

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
        points_balance=random.randint(0, 500),
        emergency_contact_name=fake.name(),
        emergency_contact_phone=fake.phone_number(),
        emergency_contact_email=fake.email(),
        photo_url=random.choice(_sample_images),
    )
