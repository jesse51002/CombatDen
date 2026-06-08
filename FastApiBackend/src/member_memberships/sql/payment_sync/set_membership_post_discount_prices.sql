-- SYSTEM writeback (service-role): write each membership's OWN post-discount
-- price onto its row, keyed by item_id. The amounts are computed at build time
-- by PaymentSyncDiscounts (each membership's plan price minus its own ongoing
-- discounts, plus its once discounts only when it is already on Stripe) and
-- threaded through SyncParams; this just persists them. total_price is therefore
-- the per-membership share, NOT a plan-level total fanned across the family.
--
-- Keyed by item_id (the membership PK), so it is inherently scoped to exactly
-- the memberships in the payload — no cross-family bleed.
--
-- NB: the functional CAST(param AS type) form is used instead of the param::type
-- shorthand because SQLAlchemy text() will not bind a parameter immediately
-- followed by a double-colon cast. (Avoid writing a colon-prefixed word in this
-- comment too — text() scans comments for bind params.)
UPDATE member_memberships_unfiltered mm
SET total_price = i.amount
FROM (
    SELECT
        (elem ->> 'item_id')::uuid AS item_id,
        (elem ->> 'amount')::int   AS amount
    FROM jsonb_array_elements(CAST(:membership_amounts AS jsonb)) AS elem
) i
WHERE mm.item_id = i.item_id
