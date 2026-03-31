import random
import uuid
from datetime import date, datetime, timedelta, timezone


def make_seeded_uuids(seed: int, count: int) -> list[uuid.UUID]:
    rng = random.Random(seed)
    return [uuid.UUID(int=rng.getrandbits(128)) for _ in range(count)]


def random_past_datetime(days_back: int) -> datetime:
    delta = timedelta(
        days=random.randint(0, days_back),
        hours=random.randint(6, 21),
        minutes=random.randint(0, 59),
    )
    return datetime.now(timezone.utc) - delta


def random_past_date(days_back: int) -> date:
    return date.today() - timedelta(days=random.randint(0, days_back))
