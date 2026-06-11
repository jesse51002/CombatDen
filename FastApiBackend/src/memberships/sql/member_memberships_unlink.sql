UPDATE members
SET
    account_linked_to_id = NULL
WHERE member_id = :member_id
RETURNING member_id
