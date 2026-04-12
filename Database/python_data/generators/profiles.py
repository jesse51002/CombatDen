import random
import uuid
from datetime import timedelta
from pathlib import Path
from typing import Optional

import yaml
from faker import Faker

from schema.user_gym_profile import UserGymProfileCreate
from utils import random_past_datetime, today_offset

_images_path = Path(__file__).parent / "sample_images.yaml"
with open(_images_path) as f:
    _sample_images: list[str] = yaml.safe_load(f)

fake = Faker()


def apply_freeze(profiles: list[UserGymProfileCreate], ratio: float = 0.15) -> None:
    """Mutate ~ratio of standalone/parent profiles to have account-level freeze dates.

    Linked (child) accounts inherit freeze from their parent via the DB view,
    so only profiles without account_linked_to_id are eligible.
    """
    for profile in profiles:
        if profile.account_linked_to_id is not None:
            continue
        if random.random() < ratio:
            freeze_start = today_offset(-random.randint(1, 30))
            freeze_duration = random.randint(7, 60)
            profile.freeze_start_date = freeze_start
            profile.freeze_end_date = freeze_start + timedelta(days=freeze_duration)


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
        stripe_customer_id=f"cus_{uuid.uuid4().hex[:24]}",
    )
