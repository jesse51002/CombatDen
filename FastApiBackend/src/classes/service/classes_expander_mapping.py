"""Pure mappers: DB rows -> the expander's input contracts.

A class-less concern module (like ``payments_stripe_mappers.py``): these are
pure row->Pydantic projections shared by every expander caller (the schedule
reader, the exceptions/undo services, the check-in resolver, the sign-up
validator, the mint engine), so the ``gym_class_schedules`` /
``class_instance_exceptions`` / ``class_range_exceptions`` row shapes map to
the expander in exactly one place.
"""

from collections.abc import Mapping

import src.shared.db_schema_path  # noqa: F401  # Register DB schema on sys.path
from src.classes.schema.classes_expander_schema import (
    ExpanderInstanceException,
    ExpanderRangeException,
    ExpanderScheduleVersion,
)

# The columns the expander reads off a gym_class_schedules version row: the
# version identity plus the flat schedule shape (per-weekday flags + slots).
_EXPANDER_SCHEDULE_KEYS: tuple[str, ...] = (
    "schedule_id",
    "class_id",
    "gym_id",
    "effective_from",
    "timezone",
    "class_time",
    "duration_minutes",
    "recurring_unit",
    "recurring_interval",
    "sun",
    "mon",
    "tue",
    "wed",
    "thu",
    "fri",
    "sat",
    "sun_instructor_id",
    "mon_instructor_id",
    "tue_instructor_id",
    "wed_instructor_id",
    "thu_instructor_id",
    "fri_instructor_id",
    "sat_instructor_id",
    "start_date",
    "end_date",
)


def to_expander_schedule(row: Mapping) -> ExpanderScheduleVersion:
    """Project a ``gym_class_schedules`` row onto the expander contract."""
    return ExpanderScheduleVersion(
        **{key: row[key] for key in _EXPANDER_SCHEDULE_KEYS}
    )


def to_expander_instance(row: Mapping) -> ExpanderInstanceException:
    """Project a ``class_instance_exceptions`` row onto the expander contract."""
    return ExpanderInstanceException(
        original_date=row["original_date"],
        is_cancelled=row["is_cancelled"],
        new_class_time=row["new_class_time"],
        new_duration_minutes=row["new_duration_minutes"],
        new_instructor_id=row["new_instructor_id"],
        new_date=row["new_date"],
        created_at=row["created_at"],
    )


def to_expander_range(row: Mapping) -> ExpanderRangeException:
    """Project a ``class_range_exceptions`` row onto the expander contract."""
    return ExpanderRangeException(
        start_date=row["start_date"],
        end_date=row["end_date"],
        is_cancelled=row["is_cancelled"],
        new_instructor_id=row["new_instructor_id"],
        created_at=row["created_at"],
    )
