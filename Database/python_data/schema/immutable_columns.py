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
        # theme_preference is intentionally NOT listed — it is the employee's own
        # client-editable CRM appearance setting (PUT /employees/me/theme).
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
        "plan_id",  # billing attribution, set once at check-in
        "item_id",  # membership row that covered the check-in
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

GYM_WAIVERS: frozenset[str] = frozenset(
    {
        "waiver_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "created_at",  # auto-generated timestamp
        "current_version_id",  # set by the publish-version flow, not a raw edit
        "is_default",  # the undeletable default; set once at seed/create
        # name + is_deleted + updated_at are the writable update surface.
    }
)

GYM_WAIVER_VERSIONS: frozenset[str] = frozenset(
    {
        # Client-immutable in full — clients never write version rows directly.
        # (The backend, at service_role, edits an UNSIGNED current version in
        # place; once a version is signed it is frozen and edits mint a new one.)
        "version_id",  # PK, auto-generated UUID
        "waiver_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "version_number",  # set by the publish flow
        "body",  # the immutable signed text
        "content_hash",  # backend-computed sha256 of body
        "created_at",  # auto-generated timestamp
    }
)

MEMBER_WAIVER_SIGNATURES: frozenset[str] = frozenset(
    {
        # Append-only legal audit record — every column user-immutable.
        "signature_id",  # PK, auto-generated UUID
        "gym_id",  # identity FK, per-gym resource
        "member_id",  # identity FK
        "waiver_id",  # identity FK
        "waiver_version_id",  # the exact version signed
        "signed_at",  # auto-generated timestamp
        "signer_name",  # captured at sign time
        "signature_type",  # captured at sign time
        "consent_acknowledged",  # captured at sign time
        "ip_address",  # audit trail, captured at sign time
        "user_agent",  # audit trail, captured at sign time
        "content_hash",  # frozen copy of the signed version's hash
    }
)

MEMBER_AUTHORIZED_PAYERS: frozenset[str] = frozenset(
    {
        # Backend-managed authorization rows — clients never write any column.
        "member_id",  # identity (the member being paid for)
        "payer_member_id",  # identity (the authorized payer / signer)
        "gym_id",  # identity FK, per-gym resource
        "signature_id",  # the gating waiver signature
        "created_at",  # auto-generated timestamp
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
        # The plan's billing model is fixed at creation — changing it would
        # break how existing members on the plan are billed (DB-enforced by
        # the trg_prevent_plan_type_overwrite trigger).
        "plan_type",
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
        # gym_discounts is identity-only: name (editable) + type
        # (preset | custom | linked). The percent/dollar + lifetime live on the
        # versioned gym_discount_values rows. A `linked` discount is a real entry
        # a membership plan's family tiers reference by id.
    }
)

GYM_DISCOUNT_VALUES: frozenset[str] = frozenset(
    {
        # Versioned, immutable value rows: every column is immutable except
        # is_active (flipped to deactivate the prior version when a new one is
        # inserted). Editing a value = a NEW version, never an UPDATE of these.
        "value_id",  # PK, auto-generated UUID
        "discount_id",  # identity FK to the owning discount
        "gym_id",  # identity FK, per-gym resource
        "percentage_off",  # immutable value
        "dollar_off",  # immutable value
        "discount_mode",  # immutable lifetime mode
        "duration_amount",  # immutable lifetime spec
        "duration_unit",  # immutable lifetime spec
        "end_date",  # immutable lifetime spec
        "created_at",  # auto-generated timestamp
        # is_active is intentionally NOT listed — the one mutable column.
    }
)

MEMBER_MEMBERSHIPS: frozenset[str] = frozenset(
    {
        "item_id",  # PK, auto-generated UUID
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "plan_id",  # immutable (trigger: trg_prevent_plan_id_overwrite)
        "paid_by_member_id",  # immutable payer (trigger: trg_prevent_paid_by_member_id_overwrite)
        "created_at",  # auto-generated timestamp
        # Stripe columns — always set by backend
        "stripe_item_id",  # immutable once set (trigger, no exceptions)
        "stripe_one_time_invoice_id",  # one-time consolidated invoice id (writeback)
        "stripe_sync_status",  # sync writeback (Stripe-convergence confirmation)
        "price_id",  # immutable (trigger: trg_prevent_price_id_overwrite); reprice = new row
        "quantity",  # set at INSERT, immutable after; recurring forced = 1 (trigger: trg_recurring_quantity_must_be_one)
    }
)

TASKS: frozenset[str] = frozenset(
    {
        # Backend-executed tracked operations: written by the backend at
        # service_role only, read-only for clients. Every column is
        # user-immutable.
        "task_id",
        "gym_id",
        "task_type",
        "status",
        "created_at",
        "started_at",
        "finished_at",
    }
)

TASK_ITEMS: frozenset[str] = frozenset(
    {
        # Per-membership work units of a task: backend-written records, every
        # column user-immutable.
        "task_item_id",
        "task_id",
        "gym_id",
        "member_id",
        "status",
        "attempt_count",
        "error_message",
        "old_item_id",
        "new_item_id",
        "target_price_id",
        "proration_behavior",
        "created_at",
        "started_at",
        "finished_at",
    }
)

MEMBER_MEMBERSHIP_APPLIED_DISCOUNTS: frozenset[str] = frozenset(
    {
        # Applied-discount rows: apply = INSERT, remove = DELETE, never an UPDATE
        # from a client. Every column is user-immutable. end_date and
        # stripe_coupon_id are outcome writebacks done only by the sync at
        # service_role.
        "applied_discount_id",  # PK, auto-generated UUID
        "item_id",  # identity FK, the membership / Stripe item
        "member_id",  # identity FK
        "gym_id",  # identity FK, per-gym resource
        "value_id",  # identity FK, the frozen discount value version
        "end_date",  # sync writeback (resolved / consumption-stamped)
        "stripe_coupon_id",  # sync writeback (resolved coupon / once handle)
        "stripe_sync_status",  # sync writeback (Stripe-convergence confirmation)
        "created_at",  # auto-generated timestamp
    }
)

MEMBER_INVOICES: frozenset[str] = frozenset(
    {
        "invoice_id",  # PK, auto-generated UUID
        "paid_by_member_id",  # identity FK — the payer
        "paid_for",  # beneficiary member_id list, set by backend at record time
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
        "paid_by_member_id",  # identity FK — the payer
        "gym_id",  # identity FK, per-gym resource
        "kind",  # set at creation
        "charge_time",  # auto-generated timestamp
        "refunds_charge_id",  # set at creation for refund rows
        # Value columns — append-only Stripe-gated table with no client UPDATE
        # path, so every column is client-immutable. Each row is written once at
        # record time (Stripe webhook or completed cash transaction), never edited.
        "status",
        "amount",
        "currency",
        "payment_method_type",
        "card_last_four",
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
