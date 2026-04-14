"""Immutable column definitions per database table.

Each variable is a frozenset of column names that must never
appear in an UPDATE SET clause. These columns are protected by
primary keys, triggers, auto-generation, or identity constraints.

Keep this file updated whenever database schemas change —
add/remove columns here to match the current schema.
"""

USER_GYM_PROFILES: frozenset[str] = frozenset(
    {
        "crm_user_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "user_id",  # trigger: trg_prevent_user_id_overwrite
        "created_at",  # auto-generated timestamp
        "last_class",  # set by checkin service, never by client
        "points_balance",  # managed by rewards system, never by client
        "total_monthly_recurring_price",  # managed by backend membership logic, never by client
        # Stripe columns — always set by backend, never by client
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
        "linked_discount_id",  # set by backend linking logic, not client
    }
)

MEMBER_MEMBERSHIPS: frozenset[str] = frozenset(
    {
        "item_id",  # PK, auto-generated UUID
        "crm_user_id",  # identity FK
        "gym_id",  # identity FK
        "plan_id",  # immutable (trigger: trg_prevent_plan_id_overwrite)
        "created_at",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_item_id",
        "price_id",
    }
)

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

GYMS: frozenset[str] = frozenset(
    {
        "gym_id",  # PK, auto-generated UUID
        # Stripe columns — always set by backend
        "stripe_account_id",
        "stripe_onboarding_status",
    }
)

GYM_CLASSES: frozenset[str] = frozenset(
    {
        "class_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

GYM_CLASS_SCHEDULES: frozenset[str] = frozenset(
    {
        "schedule_id",  # PK, auto-generated UUID
        "class_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "start_date",  # part of EXCLUDE constraint
        "created_at",  # auto-generated timestamp
    }
)

GYM_CLASS_EXCEPTIONS: frozenset[str] = frozenset(
    {
        "exception_id",  # PK, auto-generated UUID
        "schedule_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "original_date",  # part of UNIQUE constraint
        "created_at",  # auto-generated timestamp
    }
)

GYM_DISCOUNTS: frozenset[str] = frozenset(
    {
        "discount_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "discount_type",  # set at creation, determines linked constraints
        "membership_plan_id",  # linked discount identity, set at creation
        "linked_discount_num",  # linked discount sequence, set at creation
        "is_deleted",  # managed by delete endpoint only
        "created_at",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_coupon_id",
    }
)

GYM_REWARDS: frozenset[str] = frozenset(
    {
        "reward_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

GYM_HISTORY: frozenset[str] = frozenset(
    {
        "gym_id",  # composite PK
        "date",  # composite PK
    }
)

USER_GYM_INVOICES: frozenset[str] = frozenset(
    {
        "invoice_id",  # PK, auto-generated UUID
        "crm_user_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "invoice_time",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_invoice_id",
        "stripe_payment_intent_id",
        "stripe_event_payload",
    }
)

USER_GYM_INVOICE_LINE_ITEMS: frozenset[str] = frozenset(
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

USER_GYM_CHARGES: frozenset[str] = frozenset(
    {
        "charge_id",  # PK, auto-generated UUID
        "invoice_id",  # identity FK
        "crm_user_id",  # identity FK
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

USER_GYM_INVOICE_APPLIED_DISCOUNTS: frozenset[str] = frozenset(
    {
        "applied_discount_id",  # PK, auto-generated UUID
        "invoice_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "discount_id",  # identity FK
        # Stripe columns — always set by backend
        "stripe_coupon_id",
    }
)

USER_GYM_REWARD_REDEMPTIONS: frozenset[str] = frozenset(
    {
        "redemption_id",  # PK, auto-generated UUID
        "crm_user_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "reward_id",  # identity FK
        "redeemed_at",  # auto-generated timestamp
    }
)

USER_ACTIVITIES: frozenset[str] = frozenset(
    {
        "activity_id",  # PK, auto-generated UUID
        "crm_user_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "time",  # auto-generated timestamp
    }
)

GYM_CLASSES_LOG: frozenset[str] = frozenset(
    {
        "log_id",  # PK, auto-generated UUID
        "crm_user_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "class_id",  # identity FK
        "plan_id",  # identity FK
        "item_id",  # identity FK, membership item
        "time",  # auto-generated timestamp
    }
)

GYM_EMPLOYEES: frozenset[str] = frozenset(
    {
        "employee_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
    }
)

STRIPE_WEBHOOK_EVENTS: frozenset[str] = frozenset(
    {
        "event_id",  # PK, Stripe event ID
        "gym_id",  # identity FK
        "processed_at",  # auto-generated timestamp
    }
)
