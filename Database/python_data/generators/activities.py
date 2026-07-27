import random
import uuid
from datetime import UTC, datetime, timedelta

from schema.gym_rank import SubRankType, rank_display_name
from schema.member_activity import MemberActivityCreate, MemberActivityType
from utils import random_past_datetime

# Only class_attended is emitted in the random loop; rank_changed is stamped
# once per ranked member below (the member-detail progress anchor). video_clicked
# is a valid member_activity_type but is not seeded — there is no grounded
# activity_info shape for it here (no video reference to point at).
ACTIVITY_TYPES = [MemberActivityType.class_attended]

CLASS_NAMES = ["Morning BJJ", "Evening MMA", "Kickboxing", "Open Mat", "Sparring"]


def _make_info(activity_type: MemberActivityType) -> dict:
    if activity_type == MemberActivityType.class_attended:
        return {"class_name": random.choice(CLASS_NAMES)}
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
    classes_per_step: int | None,
) -> datetime:
    """Stamp the `rank_changed` anchor so a BELIEVABLE number of the
    member's OWN attendance rows land after it.

    The backend counts `classes_since_rank` as the member's `member_attendance`
    rows with `occurred_at` > this anchor (`member_details.sql`), falling back
    to `members.created_at` when there's no `rank_changed` row at all. Picking
    the anchor FROM the member's actual attendance timeline -- instead of an
    independent random point in the last 60 days -- is what makes the
    resulting progress read as real partial progress toward the member's
    immediate step denominator (`classes_per_step` -- an even split of the
    rank's classes_to_next_major across its sub-positions, or the whole
    classes_to_next_major when the rank has no sub-ranks) instead of an
    arbitrary 0/N or an impossible >N.

    Sorts the member's attendance descending (most recent first) and draws a
    small K -- via a triangular distribution skewed toward 0 so most members
    read as freshly ranked, a healthy few read partway, and only a rare few
    sit right at the door -- capped at both the member's per-step denominator
    (`classes_per_step`, the believable ceiling) and however much attendance
    the member actually has. The anchor is then placed strictly between the
    Kth-most-recent attendance row and the (K+1)th (or after the single newest
    row when K=0, or before the oldest row when K spans everything the member
    has), so exactly K rows compare `occurred_at > anchor`.

    Falls back to `random_past_datetime(60)` (the pre-existing behavior) for
    a member with no attendance rows at all -- there's nothing to anchor to.
    """
    if not attendance_times:
        return random_past_datetime(60)

    ordered = sorted(attendance_times, reverse=True)  # most recent first
    cap = (
        min(len(ordered), classes_per_step)
        if classes_per_step
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
    classes_per_step: int | None = None,
    attendance_times: list[datetime] | None = None,
    current_sub_index: int | None = None,
    sub_rank_type: SubRankType | None = None,
    current_rank_image_url: str | None = None,
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
    # them on their current LEAF, in the exact shape the backend's
    # insert_rank_activity.sql writes. This is the member-detail progress
    # anchor, so its presence and shape must match production. new_rank_name
    # is the member's leaf display name: the bare main-rank name when at the
    # base sub (or a rank with no sub-ranks), else "Main · SubLabel".
    if current_rank_id is not None:
        new_rank_name = (
            rank_display_name(current_rank_name, sub_rank_type, current_sub_index)
            if current_rank_name is not None and sub_rank_type is not None
            else current_rank_name
        )
        activities.append(
            MemberActivityCreate(
                member_id=member_id,
                gym_id=gym_id,
                activity_type=MemberActivityType.rank_changed,
                activity_info={
                    "old_rank_id": None,
                    "new_rank_id": str(current_rank_id),
                    "old_rank_name": None,
                    "new_rank_name": new_rank_name,
                    # A first assignment has no FROM leaf, so every old_* stays
                    # None. The new_* pair is snapshotted because the member
                    # app animates the belt off this row -- without the image
                    # the animation has no art to show on seeded data.
                    "old_sub_index": None,
                    "new_sub_index": current_sub_index,
                    "old_image_url": None,
                    "new_image_url": current_rank_image_url,
                },
                time=_rank_changed_anchor_time(
                    attendance_times or [], classes_per_step
                ),
            )
        )
    return activities
