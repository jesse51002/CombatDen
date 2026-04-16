-- Hard-delete a pending gym row after a Stripe create failure.
-- The ``stripe_account_id IS NULL`` guard prevents us from deleting
-- a row whose Stripe linkage just landed in a concurrent update.
DELETE FROM gyms_unfiltered
WHERE gym_id = :gym_id
  AND stripe_account_id IS NULL;
