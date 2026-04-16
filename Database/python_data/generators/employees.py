import random
import uuid

from faker import Faker
from schema.gym_employee import GymEmployeeCreate

fake = Faker()

EMPLOYEE_TYPES = ["admin", "trainer"]

EMPLOYEE_DESCRIPTIONS = [
    "Passionate coach with years of competition experience.",
    "Dedicated instructor focused on technique and fundamentals.",
    "Former professional fighter turned full-time coach.",
    "Specializes in beginner-friendly classes and personal training.",
    "Competition-focused coach with multiple championship titles.",
    "Experienced trainer with a background in strength and conditioning.",
]

EMPLOYEE_PIC_URLS = [
    "https://combat-den-seed.s3.amazonaws.com/employees/coach1.jpg",
    "https://combat-den-seed.s3.amazonaws.com/employees/coach2.jpg",
    "https://combat-den-seed.s3.amazonaws.com/employees/coach3.jpg",
    "https://combat-den-seed.s3.amazonaws.com/employees/coach4.jpg",
]


def generate_owner(
    gym_id: uuid.UUID,
    user_id: uuid.UUID,
    email: str,
    employee_id: uuid.UUID | None = None,
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
        employee_pic_url=random.choice(EMPLOYEE_PIC_URLS),
        employee_public_description=random.choice(EMPLOYEE_DESCRIPTIONS),
    )


def generate_staff(
    gym_id: uuid.UUID,
    count: int,
    user_id: uuid.UUID | None = None,
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
                employee_pic_url=random.choice(EMPLOYEE_PIC_URLS)
                if random.random() < 0.7
                else None,
                employee_public_description=random.choice(EMPLOYEE_DESCRIPTIONS)
                if random.random() < 0.7
                else None,
            )
        )
    return staff
