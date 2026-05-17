"""Generate member_status periods per member.

Periods must not overlap (gist EXCLUDE on the table enforces this).
With inclusive bounds (`[]`) on daterange, a follow-on period must
start AT LEAST one day after the previous period's end_date.
"""

from __future__ import annotations

import random
import uuid
from datetime import timedelta

from generators.members import MemberPlan
from schema.member_status import MemberStatusCreate, MemberStatusType
from utils import today_offset


def generate(gym_id: uuid.UUID, plans: list[MemberPlan]) -> list[MemberStatusCreate]:
    rows: list[MemberStatusCreate] = []
    for plan in plans:
        rows.extend(_for_plan(gym_id, plan))
    return rows


def _for_plan(gym_id: uuid.UUID, plan: MemberPlan) -> list[MemberStatusCreate]:
    trial_len = random.randint(7, 30)

    if plan.lifecycle == "in_trial":
        # Currently in trial. Trial started in the recent past and ends
        # today or in the near future (or open-ended).
        trial_end_offset = random.randint(1, 14)
        trial_start = today_offset(-(trial_len - trial_end_offset))
        trial_end = today_offset(trial_end_offset)
        return [
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.trial,
                start_date=trial_start,
                end_date=trial_end,
            )
        ]

    if plan.lifecycle == "churned_trial":
        # Trial finished some time ago, no follow-on. Currently inactive.
        trial_end = today_offset(-random.randint(1, 60))
        trial_start = trial_end - timedelta(days=trial_len)
        return [
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.trial,
                start_date=trial_start,
                end_date=trial_end,
            )
        ]

    if plan.lifecycle == "converted_full":
        # Trial completed; member transitioned to full. Full is open-ended (current).
        trial_end = today_offset(-random.randint(30, 200))
        trial_start = trial_end - timedelta(days=trial_len)
        active_start = trial_end + timedelta(days=1)  # +1 to satisfy [] no-overlap
        return [
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.trial,
                start_date=trial_start,
                end_date=trial_end,
            ),
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.full,
                start_date=active_start,
                end_date=None,
            ),
        ]

    if plan.lifecycle == "converted_then_churned":
        # Full lifecycle: trial → full → ended. Currently inactive.
        trial_end = today_offset(-random.randint(60, 200))
        trial_start = trial_end - timedelta(days=trial_len)
        active_start = trial_end + timedelta(days=1)
        active_end = active_start + timedelta(days=random.randint(30, 150))
        # Clamp to today so we don't accidentally produce a future end_date.
        active_end = min(active_end, today_offset(0))
        return [
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.trial,
                start_date=trial_start,
                end_date=trial_end,
            ),
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.full,
                start_date=active_start,
                end_date=active_end,
            ),
        ]

    if plan.lifecycle == "full_then_disabled":
        # Trial → full → disabled (still disabled today). Banned/suspended.
        trial_end = today_offset(-random.randint(60, 180))
        trial_start = trial_end - timedelta(days=trial_len)
        active_start = trial_end + timedelta(days=1)
        active_end = active_start + timedelta(days=random.randint(20, 100))
        active_end = min(active_end, today_offset(-2))
        disabled_start = active_end + timedelta(days=1)
        return [
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.trial,
                start_date=trial_start,
                end_date=trial_end,
            ),
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.full,
                start_date=active_start,
                end_date=active_end,
            ),
            MemberStatusCreate(
                status_id=uuid.uuid4(),
                member_id=plan.member_id,
                gym_id=gym_id,
                status_type=MemberStatusType.disabled,
                start_date=disabled_start,
                end_date=None,
            ),
        ]

    # never_started — no rows. Member is implicitly inactive.
    return []
