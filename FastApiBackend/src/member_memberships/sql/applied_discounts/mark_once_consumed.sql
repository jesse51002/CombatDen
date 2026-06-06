-- SYSTEM writeback (service-role): stamp end_date on the `once` discounts the
-- sync found consumed (their stored stripe_coupon_id is no longer present on the
-- subscription = Stripe already invoiced them). Recording the consumption date
-- short-circuits future presence checks: the end_date exclusion then drops the
-- row on every later run, so we stop querying Stripe for it. Stamps the whole
-- consumed set in one statement; only rows without an end_date are touched, so a
-- re-run is idempotent.
UPDATE member_membership_applied_discounts_unfiltered
SET end_date = :end_date
WHERE applied_discount_id = ANY(:applied_discount_ids)
  AND end_date IS NULL
