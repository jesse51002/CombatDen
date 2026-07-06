import random
import uuid
from datetime import UTC, datetime, timedelta

from schema.member_activity import MemberActivityCreate
from utils import random_past_datetime

ACTIVITY_TYPES = ["class_attended", "reward_redeemed", "check_in"]

CLASS_NAMES = ["Morning BJJ", "Evening MMA", "Kickboxing", "Open Mat", "Sparring"]
REWARD_NAMES = ["T-Shirt", "Guest Pass", "Protein Shake"]


def _make_info(activity_type: str) -> dict:
    if activity_type == "class_attended":
        return {"class_name": random.choice(CLASS_NAMES)}
    if activity_type == "reward_redeemed":
        return {"reward": random.choice(REWARD_NAMES)}
    return {}


def _anchor_between(earlier: datetime, later: datetime) -> datetime:
    """A random instant strictly between two UTC-aware datetimes. Falls back
    to `earlier` when the pair is too close (<2s apart) to carve out an open
    interval -- an edge case (e.g. two attendance rows a second apart), not
    the common path."""
    span = (later - earlier).total_seconds()
    if span <= 2:
        return earlier
    return earlier + timedelta(seconds=random.uniform(1, span - 1))


def _rank_changed_anchor_time(
    attendance_times: list[datetime],
    classes_till_rankup: int | None,
) -> datetime:
    """Stamp the `rank_changed` anchor so a BELIEVABLE number of the
    member's OWN attendance rows land after it.

    The backend counts `classes_since_rank` as the member's `member_attendance`
    rows with `occurred_at` > this anchor (`member_details.sql`), falling back
    to `members.created_at` when there's no `rank_changed` row at all. Picking
    the anchor FROM the member's actual attendance timeline -- instead of an
    independent random point in the last 60 days -- is what makes the
    resulting progress read as real partial progress toward the rank's
    `classes_till_rankup` threshold instead of an arbitrary 0/N or an
    impossible >N.

    Sorts the member's attendance descending (most recent first) and draws a
    small K -- via a triangular distribution skewed toward 0 so most members
    read as freshly ranked, a healthy few read partway, and only a rare few
    sit right at the door -- capped at both the rank's `classes_till_rankup`
    threshold (the believable ceiling) and however much attendance the member
    actually has. The anchor is then placed strictly between the Kth-most-
    recent attendance row and the (K+1)th (or after the single newest row
    when K=0, or before the oldest row when K spans everything the member
    has), so exactly K rows compare `occurred_at > anchor`.

    Falls back to `random_past_datetime(60)` (the pre-existing behavior) for
    a member with no attendance rows at all -- there's nothing to anchor to.
    """
    if not attendance_times:
        return random_past_datetime(60)

    ordered = sorted(attendance_times, reverse=True)  # most recent first
    cap = (
        min(len(ordered), classes_till_rankup)
        if classes_till_rankup
        else len(ordered)
    )
    k = round(random.triangular(0, cap, 0)) if cap > 0 else 0

    if k == 0:
        # 0 classes since rank -- anchor sits between the newest attendance
        # row and now (the promotion happened sometime after their last
        # logged class).
        return _anchor_between(ordered[0], datetime.now(UTC))
    if k >= len(ordered):
        # Every attendance row the member has counts -- anchor before the
        # oldest one.
        return ordered[-1] - timedelta(hours=random.uniform(1, 72))
    # k rows (the k most recent) count; anchor strictly between the kth and
    # (k+1)th most-recent rows.
    return _anchor_between(ordered[k], ordered[k - 1])


def generate(
    member_id: uuid.UUID,
    gym_id: uuid.UUID,
    count: int,
    current_rank_id: uuid.UUID | None = None,
    current_rank_name: str | None = None,
    classes_till_rankup: int | None = None,
    attendance_times: list[datetime] | None = None,
) -> list[MemberActivityCreate]:
    activities = []
    for _ in range(count):
        act_type = random.choice(ACTIVITY_TYPES)
        activities.append(
            MemberActivityCreate(
                member_id=member_id,
                gym_id=gym_id,
                activity_type=act_type,
                activity_info=_make_info(act_type),
                time=random_past_datetime(60),
            )
        )

    # One rank_changed row per RANKED member — the assignment that put
    # them on their current rank, in the exact shape the backend's
    # insert_rank_activity.sql writes. This is the member-detail
    # progress anchor, so its presence and shape must match production.
    if current_rank_id is not None:
        activities.append(
            MemberActivityCreate(
                member_id=member_id,
                gym_id=gym_id,
                activity_type="rank_changed",
                activity_info={
                    "old_rank_id": None,
                    "new_rank_id": str(current_rank_id),
                    "old_rank_name": None,
                    "new_rank_name": current_rank_name,
                },
                time=_rank_changed_anchor_time(
                    attendance_times or [], classes_till_rankup
                ),
            )
        )
    return activities
