SELECT
    c.member_id,
    c.account_linked_to_id AS candidate_linked_to,
    p.member_id AS parent_member_id,
    p.account_linked_to_id AS parent_linked_to,
    EXISTS (
        SELECT 1
        FROM member_billing_profile
        WHERE account_linked_to_id = :member_id
    ) AS candidate_is_parent
FROM member_billing_profile c
LEFT JOIN member_billing_profile p
    ON p.member_id = :parent_member_id
WHERE c.member_id = :member_id
