-- Clear a stale Stripe account linkage.
-- Used when a read operation discovers the Stripe side no longer
-- has the account (per the CLAUDE.md rule: reads that hit 404 on
-- Stripe should clear the CRM linkage so the owner can recreate).
UPDATE gyms
SET stripe_account_id     = NULL,
    stripe_onboarding_status = 'not_started'
WHERE gym_id = :gym_id
RETURNING *;
