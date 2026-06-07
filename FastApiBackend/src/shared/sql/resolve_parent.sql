SELECT
    p.member_id,
    p.gym_id,
    p.stripe_customer_id,
    p.stripe_sub_id_month,
    p.freeze_start_date,
    p.freeze_end_date,
    g.timezone
FROM member_billing_profile self_profile
JOIN member_billing_profile p
    ON p.member_id = COALESCE(self_profile.account_linked_to_id, self_profile.member_id)
   AND p.gym_id = self_profile.gym_id
JOIN gyms g ON g.gym_id = p.gym_id
WHERE self_profile.member_id = :member_id
