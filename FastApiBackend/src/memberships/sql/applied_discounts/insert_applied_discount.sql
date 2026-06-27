-- Apply a discount: INSERT a snapshot row freezing one membership (item_id) to
-- one immutable discount value version (value_id). A snapshot is never edited —
-- apply = INSERT, remove = DELETE. stripe_coupon_id is left NULL here (resolved
-- and written back by the sync). end_date is resolved at apply-time (a duration
-- span or an explicit end_date) or left NULL (forever) by the caller.
-- ``:sync_status`` is `not_added` for a
-- real apply (the writeback stamps `applied`) or `preview_add` for a dry-run
-- preview (the build's preview read includes it, the real path never bills it).
INSERT INTO member_membership_applied_discounts_unfiltered (
    item_id,
    member_id,
    gym_id,
    value_id,
    end_date,
    stripe_sync_status
)
VALUES (
    :item_id,
    :member_id,
    :gym_id,
    :value_id,
    :end_date,
    CAST(:sync_status AS stripe_sync_status)
)
RETURNING applied_discount_id
