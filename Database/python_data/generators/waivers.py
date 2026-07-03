"""Generate a gym's seeded waivers (catalog + version 1 pairs).

Mirrors the backend's WaiversCreate: the shared platform default name + body,
copied into the gym's own rows. ``generate`` builds the protected
``payer_auth`` authorized-payer agreement; ``generate_liability`` builds the
normal ``custom`` liability waiver the seed attaches to membership plans. The
``content_hash`` is sha256 of the body (matching the backend's
WAIVER_HASH_ALGO).
"""

import hashlib
import uuid

from schema.default_waiver import (
    DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME,
    DEFAULT_LIABILITY_WAIVER_NAME,
    default_authorized_payer_waiver_body,
    default_liability_waiver_body,
)
from schema.gym_waiver import GymWaiverCreate, WaiverType
from schema.gym_waiver_version import GymWaiverVersionCreate

_FIRST_VERSION_NUMBER = 1


def generate(
    gym_id: uuid.UUID,
) -> tuple[GymWaiverCreate, GymWaiverVersionCreate]:
    """Return the (payer-auth waiver, version 1) pair for a gym.

    The waiver is returned with ``current_version_id`` unset; the bootstrap
    inserts the version then points ``current_version_id`` at it (the FK
    requires the version row to exist first).
    """
    return _generate(
        gym_id,
        DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME,
        default_authorized_payer_waiver_body(),
        WaiverType.payer_auth,
    )


def generate_liability(
    gym_id: uuid.UUID,
) -> tuple[GymWaiverCreate, GymWaiverVersionCreate]:
    """Return the (liability waiver, version 1) pair for a gym.

    A normal ``custom`` waiver — the seed attaches it to the gym's membership
    plans (after the membership phase, so the seed's own starts aren't gated).
    """
    return _generate(
        gym_id,
        DEFAULT_LIABILITY_WAIVER_NAME,
        default_liability_waiver_body(),
        WaiverType.custom,
    )


def _generate(
    gym_id: uuid.UUID,
    name: str,
    body: str,
    waiver_type: WaiverType,
) -> tuple[GymWaiverCreate, GymWaiverVersionCreate]:
    content_hash = hashlib.sha256(body.encode("utf-8")).hexdigest()
    waiver_id = uuid.uuid4()
    version_id = uuid.uuid4()

    waiver = GymWaiverCreate(
        waiver_id=waiver_id,
        gym_id=gym_id,
        name=name,
        waiver_type=waiver_type,
    )
    version = GymWaiverVersionCreate(
        version_id=version_id,
        waiver_id=waiver_id,
        gym_id=gym_id,
        version_number=_FIRST_VERSION_NUMBER,
        body=body,
        content_hash=content_hash,
    )
    return waiver, version
