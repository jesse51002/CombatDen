SELECT crm_user_id
FROM user_gym_profiles
WHERE gym_id = :gym_id
  AND (
      crm_user_id = :parent_crm_user_id
      OR account_linked_to_id = :parent_crm_user_id
  )
