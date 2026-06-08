-- Gyms with a Stripe Connect account, for the invoice-fetch backstop to sweep
-- per connected account. (In production each gym has its own account; the local
-- test DB may point several seed gyms at one shared test account.)
SELECT gym_id, stripe_account_id
FROM gyms
WHERE stripe_account_id IS NOT NULL
