SELECT
    c.crm_user_id,
    c.account_linked_to_id AS candidate_linked_to,
    p.crm_user_id AS parent_crm_user_id,
    p.account_linked_to_id AS parent_linked_to,
    EXISTS (
        SELECT 1
        FROM user_gym_profiles
        WHERE account_linked_to_id = :crm_user_id
    ) AS candidate_is_parent
FROM user_gym_profiles c
LEFT JOIN user_gym_profiles p
    ON p.crm_user_id = :parent_crm_user_id
WHERE c.crm_user_id = :crm_user_id
