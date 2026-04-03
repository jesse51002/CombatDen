SELECT
    transaction_id,
    crm_user_id,
    item_id,
    item_type,
    amount_paid,
    time
FROM user_gym_transactions
WHERE gym_id = :gym_id
    AND crm_user_id = :crm_user_id
ORDER BY time DESC
