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
        # Stripe Connect columns — always set by backend, never by client
        "stripe_account_id",
        "stripe_onboarding_status",
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
        # Merged billing columns (was member_billing_profile) — managed by the
        # backend / Stripe, never by the client. Contact fields (photo_url,
        # phone, address, emergency_contact_*) are client-editable and are
        # accepted by the create/update member endpoints, so are intentionally
        # NOT listed here.
        "total_monthly_recurring_price",  # managed by backend membership logic
        "stripe_customer_id",  # trigger: trg_prevent_stripe_customer_id_overwrite
        "stripe_payment_method_id",
        "stripe_sub_id_month",
        "payment_type",
        "card_brand",
        "card_last_four",
        "card_exp_month",
        "card_exp_year",
        "freeze_start_date",  # managed by backend freeze/unfreeze logic
        "freeze_end_date",  # managed by backend freeze/unfreeze logic
        "account_linked_to_id",  # set by backend linking logic, not client
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
# CRM billing tables (restored). member_billing_profile was merged into the
# unified `members` table — its managed columns now live in MEMBERS above.
# ============================================================

MEMBERSHIP_PLANS: frozenset[str] = frozenset(
    {
        "plan_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_product_id",
    }
)

MEMBERSHIP_PLAN_PRICES: frozenset[str] = frozenset(
    {
        "price_id",  # PK, auto-generated UUID
        "plan_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_price_id",
    }
)

GYM_DISCOUNTS: frozenset[str] = frozenset(
    {
        "discount_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "discount_type",  # set at creation (preset | custom)
        "is_deleted",  # managed by the archive (delete) endpoint only
        "created_at",  # auto-generated timestamp
        # Linked columns + the old Stripe duration/coupon columns are gone:
        # linked discounts dissolved (now a snapshot marker), coupons computed
        # at sync (not on the preset), lifetime is discount_mode + a
        # duration span / explicit end_date (all user-set on the preset).
    }
)

MEMBER_MEMBERSHIPS: frozenset[str] = frozenset(
    {
        "item_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "plan_id",  # immutable (trigger: trg_prevent_plan_id_overwrite)
        "created_at",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_item_id",
        "price_id",
    }
)

MEMBER_MEMBERSHIP_APPLIED_DISCOUNTS: frozenset[str] = frozenset(
    {
        # Immutable snapshots: apply = INSERT, remove = DELETE, never an UPDATE
        # from a client. Every column is user-immutable. end_date and
        # stripe_coupon_id are outcome writebacks done only by the sync at
        # service_role.
        "applied_discount_id",  # PK, auto-generated UUID
        "item_id",  # identity FK, the membership / Stripe item
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "discount_type",  # snapshot at apply
        "source_discount_id",  # provenance snapshot at apply
        "linked_discount_planid",  # linked provenance snapshot at apply
        "linked_discount_num",  # linked level snapshot at apply
        "discount_name",  # snapshot at apply
        "percentage_off",  # snapshot intent at apply
        "dollar_off",  # snapshot intent at apply
        "discount_mode",  # snapshot at apply
        "end_date",  # sync writeback (resolved / consumption-stamped)
        "stripe_coupon_id",  # sync writeback (resolved coupon / once handle)
        "created_at",  # auto-generated timestamp
    }
)

MEMBER_INVOICES: frozenset[str] = frozenset(
    {
        "invoice_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "invoice_time",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_invoice_id",
        "stripe_payment_intent_id",
        "stripe_event_payload",
    }
)

MEMBER_INVOICE_LINE_ITEMS: frozenset[str] = frozenset(
    {
        "line_item_id",  # PK, Stripe line item id
        "invoice_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "item_id",  # identity FK, membership item
        "item_type",  # set at creation
        # Stripe columns — always set by backend
        "stripe_product_id",
    }
)

MEMBER_CHARGES: frozenset[str] = frozenset(
    {
        "charge_id",  # PK, auto-generated UUID
        "invoice_id",  # identity FK
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "kind",  # set at creation
        "charge_time",  # auto-generated timestamp
        "refunds_charge_id",  # set at creation for refund rows
        # Stripe columns — always set by backend
        "stripe_charge_id",
        "stripe_refund_id",
        "stripe_event_payload",
    }
)

MEMBER_INVOICE_APPLIED_DISCOUNTS: frozenset[str] = frozenset(
    {
        "applied_discount_id",  # PK, auto-generated UUID
        "invoice_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "discount_id",  # identity FK
        # Stripe columns — always set by backend
        "stripe_coupon_id",
    }
)

STRIPE_WEBHOOK_EVENTS: frozenset[str] = frozenset(
    {
        "event_id",  # PK, Stripe event ID
        "gym_id",  # identity FK
        "processed_at",  # auto-generated timestamp
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
