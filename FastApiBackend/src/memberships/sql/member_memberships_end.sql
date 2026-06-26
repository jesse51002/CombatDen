-- End a one-time / trial membership early by setting end_date = today
-- (→ status 'ended' in member_memberships_status). A one-time / trial membership
-- is a TERMINAL invoice with no subscription line, so ending it is a pure DB
-- write — no Stripe action. Recurring memberships use the cancel path (a Stripe
-- converge that removes the subscription line); the op rejects recurring before
-- reaching here, so trg_recurring_no_end_date is never tripped. RETURNING the
-- resolved end_date for the API.
UPDATE member_memberships_unfiltered
SET end_date = CAST(:gym_today AS DATE)
WHERE item_id   = :item_id
  AND member_id = :member_id
RETURNING end_date
