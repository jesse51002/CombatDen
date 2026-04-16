"""Direct-DB seeding for user_activities."""

from __future__ import annotations

import uuid

from constants import ACTIVITIES_PER_MEMBER
from generators import activities as activities_generator
from schema.user_gym_profile import UserGymProfileCreate
from supabase import Client


def create(
    client: Client,
    gym_id: uuid.UUID,
    profiles: list[UserGymProfileCreate],
) -> None:
    for profile in profiles:
        acts = activities_generator.generate(profile.crm_user_id, gym_id, ACTIVITIES_PER_MEMBER)
        client.table("user_activities").insert([a.to_insert_dict() for a in acts]).execute()
