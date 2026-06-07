-- Read which DISCOUNTS are already applied to one membership (item_id), via each
-- snapshot's value version -> owning discount. Used by the apply path to skip a
-- preset already applied (no duplicate snapshots). Reads the unfiltered base
-- tables so just-applied (not-yet-synced) rows are included in the reconcile.
SELECT
    ad.applied_discount_id,
    v.discount_id
FROM member_membership_applied_discounts_unfiltered ad
JOIN gym_discount_values_unfiltered v
    ON ad.value_id = v.value_id
WHERE ad.item_id = :item_id
  AND ad.member_id = :member_id
