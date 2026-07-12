import random
import uuid

from faker import Faker
from schema.gym_employee import EmployeeType, GymEmployeeCreate

fake = Faker()

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
    email: str,
    employee_id: uuid.UUID | None = None,
) -> GymEmployeeCreate:
    """The gym owner. Access is granted purely by a verified Supabase auth
    account whose email matches ``email`` (there is no more user_id FK) —
    the caller is responsible for creating that auth account with the same
    address."""
    return GymEmployeeCreate(
        employee_id=employee_id or uuid.uuid4(),
        gym_id=gym_id,
        employee_type=EmployeeType.owner,
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        phone=fake.phone_number(),
        email=email,
        employee_pic_url=random.choice(EMPLOYEE_PIC_URLS),
        employee_public_description=random.choice(EMPLOYEE_DESCRIPTIONS),
    )


def generate_accounted(
    gym_id: uuid.UUID,
    email: str,
    employee_type: EmployeeType,
    employee_id: uuid.UUID | None = None,
) -> GymEmployeeCreate:
    """A staff row (admin / front_desk / trainer) whose email matches a
    verified Supabase auth account created separately via
    ``generators.auth.create_user`` — the sole identity link now that
    gym_employees has no user_id column."""
    return GymEmployeeCreate(
        employee_id=employee_id or uuid.uuid4(),
        gym_id=gym_id,
        employee_type=employee_type,
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        phone=fake.phone_number(),
        email=email,
        employee_pic_url=random.choice(EMPLOYEE_PIC_URLS),
        employee_public_description=random.choice(EMPLOYEE_DESCRIPTIONS),
    )


def generate_pending_trainer(
    gym_id: uuid.UUID,
    email: str,
    employee_id: uuid.UUID | None = None,
) -> GymEmployeeCreate:
    """A trainer row with NO verified auth account — instructor DATA
    (name/photo shown on classes), never a login principal. Exercises the
    'pending / no verified account' state: the row carries an email, but no
    Supabase auth user is ever created for it, so no login can ever match."""
    return GymEmployeeCreate(
        employee_id=employee_id or uuid.uuid4(),
        gym_id=gym_id,
        employee_type=EmployeeType.trainer,
        first_name=fake.first_name(),
        last_name=fake.last_name(),
        phone=fake.phone_number(),
        email=email,
        employee_pic_url=random.choice(EMPLOYEE_PIC_URLS)
        if random.random() < 0.7
        else None,
        employee_public_description=random.choice(EMPLOYEE_DESCRIPTIONS)
        if random.random() < 0.7
        else None,
    )
