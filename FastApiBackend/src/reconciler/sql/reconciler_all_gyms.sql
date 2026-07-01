-- Every gym, for the NON-billing class-history materialize sweep's per-gym
-- loop. Not Stripe-Connect-scoped (unlike reconciler_gyms_with_connect.sql):
-- a gym with no billing set up still has classes and check-in, so every gym
-- must be swept, not just the ones with a Connect account.
SELECT gym_id FROM gyms
