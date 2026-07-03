"""Direct-DB seeding for a gym's waivers (payer-auth + liability)."""

from __future__ import annotations

import uuid

from generators import waivers as waivers_generator
from schema.gym_waiver import GymWaiverCreate
from schema.gym_waiver_version import GymWaiverVersionCreate
from supabase import Client


def create(client: Client, gym_id: uuid.UUID) -> None:
    """Seed the gym's undeletable payer-auth waiver (catalog + v1 + pointer)."""
    _insert(client, *waivers_generator.generate(gym_id))


def create_liability(client: Client, gym_id: uuid.UUID) -> uuid.UUID:
    """Seed the gym's liability waiver (a normal ``custom`` waiver).

    Returns the new waiver_id so the seed can attach it to the gym's
    membership plans AFTER the membership phase (attaching earlier would gate
    the seed's own membership starts).
    """
    waiver, version = waivers_generator.generate_liability(gym_id)
    _insert(client, waiver, version)
    return waiver.waiver_id


def _insert(
    client: Client,
    waiver: GymWaiverCreate,
    version: GymWaiverVersionCreate,
) -> None:
    """Insert catalog row (``current_version_id`` NULL), version 1, pointer.

    The same order the backend uses, because the
    ``gym_waivers.current_version_id`` FK requires the version row to exist
    first.
    """
    client.table("gym_waivers").insert(waiver.to_insert_dict()).execute()
    client.table("gym_waiver_versions").insert(
        version.to_insert_dict()
    ).execute()
    client.table("gym_waivers").update(
        {"current_version_id": str(version.version_id)}
    ).eq("waiver_id", str(waiver.waiver_id)).execute()
