-- End a one-time / trial membership early — a HUMAN-initiated termination, so
-- it writes cancel_date (→ status 'cancelled' in member_memberships_status),
-- NEVER end_date. The convention: cancel_date = manual (owner/staff/member
-- terminates early); end_date = automatic (depletion auto-end, the
-- duration-derived expiry stamped at purchase). The split is what lets the
-- check-in reversal safely restore end_date on an un-depleted pack — a manual
-- termination lives in cancel_date and is never resurrected by attendance
-- removal. A one-time / trial membership is a TERMINAL invoice with no
-- subscription line, so ending it is a pure DB write — no Stripe action.
-- Recurring memberships use the cancel path (a Stripe converge that removes
-- the subscription line); the op rejects recurring before reaching here.
-- RETURNING the resolved termination date for the API.
UPDATE member_memberships_unfiltered
SET cancel_date = CAST(:gym_today AS DATE)
WHERE item_id   = :item_id
  AND member_id = :member_id
RETURNING cancel_date
