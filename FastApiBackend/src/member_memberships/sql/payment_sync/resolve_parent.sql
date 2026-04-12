SELECT
    p.crm_user_id,
    p.gym_id,
    p.stripe_customer_id,
    p.stripe_sub_id_month,
    p.freeze_start_date,
    p.freeze_end_date
FROM user_gym_profiles self_profile
JOIN user_gym_profiles p
    ON p.crm_user_id = COALESCE(self_profile.account_linked_to_id, self_profile.crm_user_id)
   AND p.gym_id = self_profile.gym_id
WHERE self_profile.crm_user_id = :crm_user_id
