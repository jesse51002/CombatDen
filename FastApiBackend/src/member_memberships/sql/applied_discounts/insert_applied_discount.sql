-- Apply a discount: INSERT a snapshot row freezing one membership (item_id) to
-- one immutable discount value version (value_id). A snapshot is never edited —
-- apply = INSERT, remove = DELETE. stripe_coupon_id is left NULL here (resolved
-- and written back by the sync). end_date is resolved at apply-time (ongoing) or
-- left NULL (once / forever) by the caller.
INSERT INTO member_membership_applied_discounts_unfiltered (
    item_id,
    member_id,
    gym_id,
    value_id,
    end_date
)
VALUES (
    :item_id,
    :member_id,
    :gym_id,
    :value_id,
    :end_date
)
RETURNING applied_discount_id
