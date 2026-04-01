import random
import uuid
from typing import Optional

from faker import Faker

from schema.gym_employee import GymEmployeeCreate

fake = Faker()

EMPLOYEE_TYPES = ["admin", "trainer"]


def generate_owner(
    gym_id: uuid.UUID,
    user_id: uuid.UUID,
    email: str,
    employee_id: Optional[uuid.UUID] = None,
) -> GymEmployeeCreate:
    return GymEmployeeCreate(
        employee_id=employee_id or uuid.uuid4(),
        user_id=user_id,
        gym_id=gym_id,
        employee_type="owner",
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        phone=fake.phone_number(),
        email=email,
    )


def generate_staff(
    gym_id: uuid.UUID,
    count: int,
    user_id: Optional[uuid.UUID] = None,
) -> list[GymEmployeeCreate]:
    staff = []
    for _ in range(count):
        staff.append(
            GymEmployeeCreate(
                employee_id=uuid.uuid4(),
                user_id=user_id,
                gym_id=gym_id,
                employee_type=random.choice(EMPLOYEE_TYPES),
                first_name=fake.first_name(),
                last_name=fake.last_name(),
                phone=fake.phone_number(),
                email=fake.email(),
            )
        )
    return staff
