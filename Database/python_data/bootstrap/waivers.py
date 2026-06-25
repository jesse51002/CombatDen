"""Direct-DB seeding for a gym's undeletable default authorized-payer waiver."""

from __future__ import annotations

import uuid

from generators import waivers as waivers_generator
from supabase import Client


def create(client: Client, gym_id: uuid.UUID) -> None:
    """Seed the gym's default authorized-payer waiver (catalog + v1 + pointer).

    Inserts the catalog row (``current_version_id`` NULL), then version 1, then
    points ``current_version_id`` at it — the same order the backend uses,
    because the ``gym_waivers.current_version_id`` FK requires the version row
    to exist first.
    """
    waiver, version = waivers_generator.generate(gym_id)
    client.table("gym_waivers").insert(waiver.to_insert_dict()).execute()
    client.table("gym_waiver_versions").insert(
        version.to_insert_dict()
    ).execute()
    client.table("gym_waivers").update(
        {"current_version_id": str(version.version_id)}
    ).eq("waiver_id", str(waiver.waiver_id)).execute()
