-- Read a single gym's Stripe Connect state by gym id, for the
-- onboarding status/link endpoints. The caller's ownership of the
-- gym is verified at the router layer (verify_gym_owner) before
-- this runs, so this query is keyed purely on gym_id.
SELECT gym_id,
       stripe_account_id,
       stripe_onboarding_status
FROM gyms
WHERE gym_id = :gym_id;
