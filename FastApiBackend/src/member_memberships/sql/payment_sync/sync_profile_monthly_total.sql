-- Write the full monthly recurring charge for a subscription onto
-- the parent account's members row. Backend-managed
-- column (see immutable_columns.py) -- bypasses the client
-- mutability guard.
UPDATE members
SET total_monthly_recurring_price = :total_monthly_recurring_price
WHERE member_id = :member_id
