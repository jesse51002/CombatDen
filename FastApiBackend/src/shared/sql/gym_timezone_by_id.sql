-- Read a gym's IANA timezone so the webhook can convert Stripe period
-- timestamps to gym-local DATES (last_paid_date / next_due_date), consistent
-- with how start_date / end_date are stored. Service-role read.
SELECT timezone
FROM gyms
WHERE gym_id = :gym_id
