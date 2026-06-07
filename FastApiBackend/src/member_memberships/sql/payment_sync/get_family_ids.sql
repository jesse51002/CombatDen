SELECT member_id
FROM member_billing_profile
WHERE gym_id = :gym_id
  AND (
      member_id = :parent_member_id
      OR account_linked_to_id = :parent_member_id
  )
