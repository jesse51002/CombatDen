-- Insert a pending gym row with NULL stripe_account_id.
-- Invisible through the ``gyms`` filtered view until the stripe
-- account id is set by the second UPDATE step.
INSERT INTO gyms_unfiltered (gym_name, stripe_account_id)
VALUES (:gym_name, NULL)
RETURNING *;
