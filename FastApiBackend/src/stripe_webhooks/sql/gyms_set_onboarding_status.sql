-- Update the Stripe onboarding status for a gym.
-- Used by the account.updated webhook handler.
-- Does not modify stripe_account_id.
UPDATE gyms
SET stripe_onboarding_status = :status
WHERE gym_id = :gym_id
RETURNING *;
