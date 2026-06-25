"""Generate a gym's default authorized-payer waiver (catalog + version 1).

Mirrors the backend's WaiversCreate.create_default_waiver: the shared platform
default name + body, copied into the gym's own ``is_default`` waiver. The
``content_hash`` is sha256 of the body (matching the backend's WAIVER_HASH_ALGO).
"""

import hashlib
import uuid

from schema.default_waiver import (
    DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME,
    default_authorized_payer_waiver_body,
)
from schema.gym_waiver import GymWaiverCreate
from schema.gym_waiver_version import GymWaiverVersionCreate

_FIRST_VERSION_NUMBER = 1


def generate(
    gym_id: uuid.UUID,
) -> tuple[GymWaiverCreate, GymWaiverVersionCreate]:
    """Return the (default waiver, version 1) pair for a gym.

    The waiver is returned with ``current_version_id`` unset; the bootstrap
    inserts the version then points ``current_version_id`` at it (the FK
    requires the version row to exist first).
    """
    body = default_authorized_payer_waiver_body()
    content_hash = hashlib.sha256(body.encode("utf-8")).hexdigest()
    waiver_id = uuid.uuid4()
    version_id = uuid.uuid4()

    waiver = GymWaiverCreate(
        waiver_id=waiver_id,
        gym_id=gym_id,
        name=DEFAULT_AUTHORIZED_PAYER_WAIVER_NAME,
        is_default=True,
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
