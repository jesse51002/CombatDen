import random
import uuid

from schema.gym import GymCreate

NAME_PREFIXES = [
    "Iron",
    "Dragon",
    "Phoenix",
    "Tiger",
    "Apex",
    "Elite",
    "Warrior",
    "Thunder",
    "Storm",
    "Shadow",
    "Titan",
    "Viper",
]
NAME_SUFFIXES = [
    "MMA",
    "Dojo",
    "Academy",
    "Fight Club",
    "Martial Arts",
    "Combat",
    "Training Center",
    "Gym",
    "Athletics",
]

DESCRIPTION_TEMPLATES = [
    "World-class {style} training for all skill levels. Join our community of dedicated martial artists.",
    "Premier {style} facility offering expert instruction and a supportive training environment.",
    "Train with champions. Our {style} programs build discipline, fitness, and self-defense skills.",
    "Welcome to the best {style} experience in town. Classes for beginners to advanced competitors.",
]

STYLES = [
    "MMA",
    "Brazilian Jiu-Jitsu",
    "Muay Thai",
    "boxing",
    "wrestling",
    "martial arts",
]

# Real, internally-consistent US street/city/state/ZIP combos (no mixing a
# Texas city with a California ZIP, etc). These get handed to the phone's
# native maps app, so they need to actually resolve.
STREET_ADDRESSES = [
    ("2847 Riverside Dr", "Austin", "TX", "78741"),
    ("1150 W Fullerton Ave", "Chicago", "IL", "60614"),
    ("930 Sunset Blvd", "Los Angeles", "CA", "90026"),
    ("415 Broadway", "Denver", "CO", "80203"),
    ("2200 NW 2nd Ave", "Miami", "FL", "33127"),
    ("718 Grand Ave", "Seattle", "WA", "98104"),
    ("1301 S Congress Ave", "Austin", "TX", "78704"),
    ("55 Battery St", "San Francisco", "CA", "94111"),
    ("3401 Lindbergh Blvd", "Atlanta", "GA", "30354"),
    ("890 W Chicago Ave", "Chicago", "IL", "60642"),
    ("620 E 6th St", "Austin", "TX", "78701"),
    ("4520 Camp Bowie Blvd", "Fort Worth", "TX", "76107"),
    ("2101 N Damen Ave", "Chicago", "IL", "60647"),
    ("711 3rd Ave", "New York", "NY", "10017"),
    ("1550 S Michigan Ave", "Chicago", "IL", "60605"),
    ("3630 SW 22nd St", "Miami", "FL", "33145"),
    ("9200 Wilshire Blvd", "Beverly Hills", "CA", "90212"),
    ("512 W 9th St", "Kansas City", "MO", "64105"),
    ("1802 N Milwaukee Ave", "Chicago", "IL", "60647"),
    ("7000 N Mopac Expy", "Austin", "TX", "78731"),
]


def _format_address(entry: tuple[str, str, str, str]) -> str:
    street, city, state, zip_code = entry
    return f"{street}, {city}, {state} {zip_code}"


def generate(
    gym_id: uuid.UUID | None = None,
    stripe_account_id: str | None = None,
    index: int | None = None,
) -> GymCreate:
    """Build one seeded gym.

    `index` (the gym's 0-based position in the seed run, passed by
    bootstrap/gyms.py) picks the address DETERMINISTICALLY from a fixed
    lookup rather than consuming any randomness -- this must NOT touch
    `random`/`Faker`, because both are seeded once at the top of the whole
    seed run and every other generator (members, memberships, etc.) depends
    on that shared sequence staying stable regardless of what runs before it.

    EVERY seeded gym gets an address, including index 0. NUM_GYMS is 1 in the
    default dev seed, so a null-address gym 0 would mean the only gym anyone
    can log into has no address -- making the member app's address row and
    "Open in Maps" action untestable. The "no address set" empty state is
    reached instead by clearing the field in the CRM, which is a real owner
    flow and needs no seeded gym of its own.
    """
    resolved_gym_id = gym_id or uuid.uuid4()
    name = f"{random.choice(NAME_PREFIXES)} {random.choice(NAME_SUFFIXES)}"
    description = random.choice(DESCRIPTION_TEMPLATES).format(style=random.choice(STYLES))

    if index is None:
        # No index supplied (e.g. a direct/standalone call) -- fall back to a
        # deterministic pick derived from the gym_id itself. Still touches no
        # shared randomness.
        address = _format_address(STREET_ADDRESSES[resolved_gym_id.int % len(STREET_ADDRESSES)])
    else:
        address = _format_address(STREET_ADDRESSES[index % len(STREET_ADDRESSES)])

    return GymCreate(
        gym_id=resolved_gym_id,
        gym_name=name,
        gym_description=description,
        stripe_account_id=stripe_account_id,
        address=address,
    )
