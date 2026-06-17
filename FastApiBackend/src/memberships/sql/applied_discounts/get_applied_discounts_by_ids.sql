-- SYSTEM read (service-role): the applied-discount rows for a set of ids, off the
-- unfiltered base so half-synced rows are visible. Backs the add-discounts verify
-- (each row's stripe_sync_status) and the remove-discounts revert snapshot (the
-- fields needed to re-insert a removed row at its original value version).
SELECT
    applied_discount_id,
    item_id,
    member_id,
    gym_id,
    value_id,
    end_date,
    stripe_sync_status
FROM member_membership_applied_discounts_unfiltered
WHERE applied_discount_id = ANY(:applied_discount_ids)
