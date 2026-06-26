-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Applies three billing schema fixes reaching the end state declared in:
--   schemas/member_invoice_applied_discounts.sql  (C-049)
--   schemas/member_charges.sql                    (C-083)
--   schemas/member_memberships.sql                (C-086)

-- ============================================================
-- C-049 — member_invoice_applied_discounts
--   ADD line_item_id column; swap the unique constraint from
--   (invoice_id, stripe_coupon_id) to the 3-column
--   (invoice_id, stripe_coupon_id, line_item_id) form so
--   a coupon shared across sibling lines records one row per
--   line rather than collapsing into one.
-- ============================================================

-- 1a. Add the new column. Guard the empty-table assumption (data is reset
--     before applying) so a populated table fails loud, not partway.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM member_invoice_applied_discounts) THEN
        RAISE EXCEPTION
            'member_invoice_applied_discounts non-empty; line_item_id NOT NULL needs a backfill';
    END IF;
END $$;

ALTER TABLE member_invoice_applied_discounts
    ADD COLUMN line_item_id VARCHAR NOT NULL;

-- 1b. Drop the old 2-column unique constraint.
ALTER TABLE member_invoice_applied_discounts
    DROP CONSTRAINT uq_applied_discount_invoice_coupon;

-- 1c. Add the replacement 3-column unique constraint.
--     Idempotent on webhook re-delivery: one row per coupon per invoice LINE.
ALTER TABLE member_invoice_applied_discounts
    ADD CONSTRAINT uq_applied_discount_invoice_coupon_line
        UNIQUE (invoice_id, stripe_coupon_id, line_item_id);

-- ============================================================
-- C-083 — member_charges
--   Partial UNIQUE index for cash-payment idempotency so the
--   twice-daily reconciler can use ON CONFLICT DO NOTHING to
--   avoid double-recording a succeeded cash payment on the
--   same invoice.
-- ============================================================

-- 2a. Deduplicate any pre-existing succeeded-cash-payment rows per invoice,
--     keeping the earliest by (charge_time, charge_id). This is a no-op on a
--     reset DB but makes the CREATE UNIQUE INDEX safe on a populated one.
DELETE FROM member_charges
WHERE charge_id IN (
    SELECT charge_id
    FROM (
        SELECT charge_id,
               ROW_NUMBER() OVER (
                   PARTITION BY invoice_id
                   ORDER BY charge_time ASC, charge_id ASC
               ) AS rn
        FROM member_charges
        WHERE stripe_charge_id IS NULL
          AND kind = 'payment'
          AND status = 'succeeded'
          AND payment_method_type = 'cash'
    ) ranked
    WHERE rn > 1
);

-- 2b. Create the partial unique index (mirrors schemas/member_charges.sql exactly).
CREATE UNIQUE INDEX idx_charges_cash_payment_dedup
    ON member_charges (invoice_id)
    WHERE stripe_charge_id IS NULL
      AND kind = 'payment'
      AND status = 'succeeded'
      AND payment_method_type = 'cash';

-- ============================================================
-- C-086 — member_memberships_unfiltered
--   ADD idempotency_key column; partial UNIQUE index so a
--   retried one-time-membership start request collides and the
--   INSERT's ON CONFLICT DO NOTHING drops duplicate rows.
--   NULL for recurring + preview rows (unconstrained by design).
-- ============================================================

-- 3a. Add the column (nullable; NULL for recurring and preview rows).
ALTER TABLE member_memberships_unfiltered
    ADD COLUMN idempotency_key UUID;

-- 3b. Partial unique index (idempotency_key IS NOT NULL) so recurring rows
--     (NULL key) are unconstrained and distinct purchases (different key)
--     never collide.
CREATE UNIQUE INDEX idx_member_memberships_idempotency_key
    ON member_memberships_unfiltered (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- Views NOT recreated: member_memberships and member_memberships_status both
-- SELECT * from member_memberships_unfiltered. ADD COLUMN is non-destructive
-- and does not break those views. idempotency_key is a backend-only INSERT-time
-- dedup token that clients never read through the view (the conflict-resolution
-- INSERT targets the base table directly), so view recreation is not required.
