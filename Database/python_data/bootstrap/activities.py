"""Direct-DB seeding for member_activities."""

from __future__ import annotations

import math
import uuid
from collections import defaultdict
from datetime import datetime

from constants import ACTIVITIES_PER_MEMBER
from generators import activities as activities_generator
from schema.gym_class import MemberAttendanceCreate
from schema.gym_rank import GymRankCreate, SubRankType
from schema.member import MemberCreate
from supabase import Client


def _step_denominator(rank: GymRankCreate) -> int:
    """The member's immediate step denominator: an even split of the rank's
    classes_to_next_major across its sub-positions (ceil), or the whole
    classes_to_next_major when the rank has no sub-ranks."""
    if rank.sub_rank_count > 0:
        return math.ceil(rank.classes_to_next_major / rank.sub_rank_count)
    return rank.classes_to_next_major


def _leaf_image_url(rank: GymRankCreate | None, sub_index: int | None) -> str | None:
    """The belt art for one leaf: the sub-rank override when there is one,
    else the main rank's image.

    Same precedence as the backend's RanksBase._leaf_image_url
    (COALESCE(sub_rank_image_overrides ->> sub_index, image_url)), so a seeded
    rank_changed row snapshots the same art a real promotion would.
    """
    if rank is None:
        return None
    if sub_index is not None:
        override = (rank.sub_rank_image_overrides or {}).get(str(sub_index))
        if override:
            return override
    return rank.image_url


def create(
    client: Client,
    gym_id: uuid.UUID,
    members: list[MemberCreate],
    ranks: list[GymRankCreate],
    attendance: list[MemberAttendanceCreate],
    sub_rank_type: SubRankType,
) -> None:
    ranks_by_id = {r.rank_id: r for r in ranks}

    # Each member's own attendance timestamps -- the rank_changed anchor is
    # stamped from these so classes_since_rank reads as believable partial
    # progress instead of an arbitrary/impossible value (see
    # generators.activities._rank_changed_anchor_time).
    attendance_times_by_member: dict[uuid.UUID, list[datetime]] = defaultdict(list)
    for a in attendance:
        attendance_times_by_member[a.member_id].append(a.occurred_at)

    for m in members:
        rank = ranks_by_id.get(m.current_rank_id)
        rows = activities_generator.generate(
            m.member_id,
            gym_id,
            ACTIVITIES_PER_MEMBER,
            current_rank_id=m.current_rank_id,
            # Bare main-rank name; generate() derives the per-member leaf label
            # from the gym's sub_rank_type + this member's current_sub_index.
            current_rank_name=rank.name if rank else None,
            classes_per_step=_step_denominator(rank) if rank else None,
            attendance_times=attendance_times_by_member.get(m.member_id),
            current_sub_index=m.current_sub_index,
            sub_rank_type=sub_rank_type,
            current_rank_image_url=_leaf_image_url(rank, m.current_sub_index),
        )
        client.table("member_activities").insert([r.to_insert_dict() for r in rows]).execute()
