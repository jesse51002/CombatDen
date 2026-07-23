-- Raw applied invoice discounts for the gym (one row per coupon per line). No
-- timestamp of their own, so ordered by invoice id then the applied-discount id.
SELECT
    ad.applied_discount_id,
    ad.invoice_id,
    ad.gym_id,
    ad.discount_id,
    ad.line_item_id,
    ad.amount_off,
    ad.stripe_coupon_id
FROM member_invoice_applied_discounts ad
WHERE ad.gym_id = CAST(:gym_id AS UUID)
ORDER BY ad.invoice_id ASC, ad.applied_discount_id ASC
