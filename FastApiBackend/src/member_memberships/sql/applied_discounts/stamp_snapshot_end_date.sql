-- SYSTEM writeback (service-role): stamp end_date on a `once` snapshot the sync
-- found consumed (its stored stripe_coupon_id is no longer present on the
-- subscription = Stripe already invoiced it). Recording the consumption date
-- short-circuits future presence checks: the end_date exclusion then drops the
-- snapshot on every later run, so we stop querying Stripe for it. Only stamps a
-- row that does not already carry an end_date, so a re-run is idempotent.
UPDATE member_membership_applied_discounts_unfiltered
SET end_date = :end_date
WHERE applied_discount_id = :applied_discount_id
  AND end_date IS NULL
