"""Immutable column definitions per database table.

Each variable is a frozenset of column names that must never
appear in an UPDATE SET clause from a user-facing update request.
These columns are protected by primary keys, triggers,
auto-generation, or identity constraints.

Keep this file updated whenever database schemas change.
"""

GYMS: frozenset[str] = frozenset(
    {
        "gym_id",  # PK, auto-generated UUID
    }
)

GYM_EMPLOYEES: frozenset[str] = frozenset(
    {
        "employee_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

MEMBERS: frozenset[str] = frozenset(
    {
        "member_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "user_id",  # trigger: trg_prevent_user_id_overwrite
        "created_at",  # auto-generated timestamp
        "last_class",  # set by check-in service, never by client
        "points_balance",  # managed by rewards system, never by client
    }
)

MEMBER_STATUS: frozenset[str] = frozenset(
    {
        "status_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "status_type",  # set at creation
        "created_at",  # auto-generated timestamp
    }
)

MEMBER_ACTIVE: frozenset[str] = frozenset(
    {
        "active_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "active_type",  # set at creation
        "created_at",  # auto-generated timestamp
    }
)

GYM_CLASSES: frozenset[str] = frozenset(
    {
        "class_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

CLASS_INSTANCE_EXCEPTIONS: frozenset[str] = frozenset(
    {
        "exception_id",  # PK, auto-generated UUID
        "class_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "original_date",  # part of UNIQUE constraint
        "created_at",  # auto-generated timestamp
    }
)

CLASS_RANGE_EXCEPTIONS: frozenset[str] = frozenset(
    {
        "exception_id",  # PK, auto-generated UUID
        "class_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

CLASS_HISTORY: frozenset[str] = frozenset(
    {
        "class_history_id",  # PK, auto-generated UUID
        "class_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

MEMBER_ATTENDANCE: frozenset[str] = frozenset(
    {
        "log_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "class_history_id",  # identity FK
    }
)

RANK_PRESETS: frozenset[str] = frozenset(
    {
        "preset_id",  # PK, auto-generated UUID
        "gym_type",  # part of UNIQUE constraint
        "created_at",  # auto-generated timestamp
    }
)

GYM_RANKS: frozenset[str] = frozenset(
    {
        "rank_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

GYM_REWARDS: frozenset[str] = frozenset(
    {
        "reward_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

MEMBER_REWARD_REDEMPTIONS: frozenset[str] = frozenset(
    {
        "redemption_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "reward_id",  # identity FK
        "redeemed_at",  # auto-generated timestamp
    }
)

GYM_HISTORY: frozenset[str] = frozenset(
    {
        "gym_id",  # composite PK
        "date",  # composite PK
    }
)

MEMBER_ACTIVITIES: frozenset[str] = frozenset(
    {
        "activity_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "time",  # auto-generated timestamp
    }
)

# ============================================================
# VideoService demo content (video_* tables). Written by service-role only
# (no user-facing updates), but kept in sync per the Database convention.
# ============================================================

VIDEO_GYM: frozenset[str] = frozenset(
    {
        "gym_id",  # PK (text id == YAML filename stem)
    }
)

VIDEO_GYM_QUERY: frozenset[str] = frozenset(
    {
        "query_id",  # PK, identity
        "gym_id",  # identity FK, per-gym resource
    }
)

VIDEO_GYM_CLASS: frozenset[str] = frozenset(
    {
        "class_id",  # PK, identity
        "gym_id",  # identity FK, per-gym resource
    }
)

VIDEO_GYM_REWARD: frozenset[str] = frozenset(
    {
        "reward_id",  # PK, identity
        "gym_id",  # identity FK, per-gym resource
    }
)

VIDEO: frozenset[str] = frozenset(
    {
        "video_id",  # PK (YouTube id)
    }
)

VIDEO_GYM_FEED: frozenset[str] = frozenset(
    {
        "gym_id",  # composite PK / identity FK
        "video_id",  # composite PK / identity FK
    }
)

VIDEO_COST_LOG: frozenset[str] = frozenset(
    {
        "entry_id",  # PK, identity (append-only)
        "gym_id",  # identity FK, set at insert (append-only)
    }
)
