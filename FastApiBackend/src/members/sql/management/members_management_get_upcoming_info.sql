-- Resolve the paying account for a member and return the data needed to
-- fetch its upcoming (next) Stripe invoice: the parent's monthly
-- subscription id and the gym's Connect account id. A linked child resolves
-- to its parent (COALESCE(account_linked_to_id, member_id)); an unlinked
-- member resolves to itself.
SELECT
    p.stripe_sub_id_month,
    g.stripe_account_id,
    p.gym_id
FROM member_billing_profile self_profile
JOIN member_billing_profile p
    ON p.member_id = COALESCE(
        self_profile.account_linked_to_id, self_profile.member_id
    )
   AND p.gym_id = self_profile.gym_id
JOIN gyms g ON g.gym_id = p.gym_id
WHERE self_profile.member_id = :member_id
