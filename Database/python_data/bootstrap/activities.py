"""Direct-DB seeding for member_activities."""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import datetime

from constants import ACTIVITIES_PER_MEMBER
from generators import activities as activities_generator
from schema.gym_class import MemberAttendanceCreate
from schema.gym_rank import GymRankCreate
from schema.member import MemberCreate
from supabase import Client


def create(
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberCreate],
    ranks: list[GymRankCreate],
    attendance: list[MemberAttendanceCreate],
) -> None:
    rank_names = {
        r.rank_id: f"{r.main_name} {r.sub_name}".strip() for r in ranks
    }
    rank_thresholds = {r.rank_id: r.classes_till_rankup for r in ranks}

    # Each member's own attendance timestamps -- the rank_changed anchor is
    # stamped from these so classes_since_rank reads as believable partial
    # progress instead of an arbitrary/impossible value (see
    # generators.activities._rank_changed_anchor_time).
    attendance_times_by_member: dict[uuid.UUID, list[datetime]] = defaultdict(list)
    for a in attendance:
        attendance_times_by_member[a.member_id].append(a.occurred_at)

    for m in members:
        rows = activities_generator.generate(
            m.member_id,
            gym_id,
            ACTIVITIES_PER_MEMBER,
            current_rank_id=m.current_rank_id,
            current_rank_name=rank_names.get(m.current_rank_id),
            classes_till_rankup=rank_thresholds.get(m.current_rank_id),
            attendance_times=attendance_times_by_member.get(m.member_id),
        )
        client.table("member_activities").insert([r.to_insert_dict() for r in rows]).execute()
