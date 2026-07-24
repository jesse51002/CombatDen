-- Applied invoice discounts (one row per coupon per line) for the gym's
-- invoices in the report window. Windowed on the parent invoice's invoice_time
-- since the applied-discount row carries no timestamp. amount_off is raw cents;
-- the service converts to dollars.
SELECT
    inv.invoice_time,
    ad.invoice_id,
    ad.applied_discount_id,
    ad.line_item_id,
    ad.amount_off,
    ad.stripe_coupon_id,
    ad.discount_id
FROM member_invoice_applied_discounts ad
JOIN member_invoices inv
    ON inv.invoice_id = ad.invoice_id
WHERE ad.gym_id = CAST(:gym_id AS UUID)
  AND (
      CAST(:all_time AS BOOLEAN)
      OR (
          inv.invoice_time >= CAST(:start_utc AS TIMESTAMPTZ)
          AND inv.invoice_time < CAST(:end_utc AS TIMESTAMPTZ)
      )
  )
ORDER BY inv.invoice_time ASC, ad.invoice_id ASC, ad.applied_discount_id ASC
