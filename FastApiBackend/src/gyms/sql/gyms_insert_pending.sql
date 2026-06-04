-- Insert a pending gym row with NULL stripe_account_id.
-- Invisible through Stripe-keyed queries until the stripe_account_id
-- is set by the subsequent UPDATE step.
INSERT INTO gyms (gym_name, gym_description, timezone)
VALUES (:gym_name, :gym_description, :timezone)
RETURNING gym_id, gym_name, gym_description, timezone,
          stripe_account_id, stripe_onboarding_status;
