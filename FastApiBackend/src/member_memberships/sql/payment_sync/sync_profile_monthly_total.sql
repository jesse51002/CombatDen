-- Write the full monthly recurring charge for a subscription onto
-- the parent account's user_gym_profile row. Backend-managed column
-- (see immutable_columns.py) — bypasses the client mutability guard.
UPDATE user_gym_profiles_unfiltered
SET total_monthly_recurring_price = :total_monthly_recurring_price
WHERE crm_user_id = :crm_user_id
