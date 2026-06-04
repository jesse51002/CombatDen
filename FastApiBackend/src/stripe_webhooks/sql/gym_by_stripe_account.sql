SELECT gym_id
FROM gyms
WHERE stripe_account_id = :stripe_account_id
LIMIT 1
