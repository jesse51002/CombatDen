-- Attach the Stripe Connect account id to a pending gym row.
-- The ``stripe_account_id IS NULL`` guard ensures we never overwrite
-- an already-linked account.
UPDATE gyms
SET stripe_account_id     = :stripe_account_id,
    stripe_onboarding_status = 'pending'
WHERE gym_id              = :gym_id
  AND stripe_account_id IS NULL
RETURNING *;
