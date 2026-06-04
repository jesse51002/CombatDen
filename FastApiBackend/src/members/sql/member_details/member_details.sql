WITH target_profile AS (
    SELECT mbp.member_id, mbp.gym_id, mbp.account_linked_to_id
    FROM member_billing_profile mbp
    WHERE mbp.member_id = :member_id
),
primary_id AS (
    SELECT COALESCE(t.account_linked_to_id, t.member_id) AS id
    FROM target_profile t
),
family_group AS (
    SELECT mbp.member_id
    FROM member_billing_profile mbp
    JOIN target_profile t ON mbp.gym_id = t.gym_id
    CROSS JOIN primary_id pi
    WHERE mbp.member_id = pi.id
       OR mbp.account_linked_to_id = pi.id
),
latest_memberships AS (
    SELECT DISTINCT ON (member_id, gym_id, plan_id) *
    FROM member_memberships_status
    ORDER BY member_id, gym_id, plan_id,
             start_date DESC, created_at DESC
)
SELECT
    m.member_id,
    m.gym_id,
    m.first_name,
    m.last_name,
    mbp.photo_url,
    mbp.phone,
    m.email,
    mbp.address,
    mbp.emergency_contact_name,
    mbp.emergency_contact_phone,
    mbp.emergency_contact_email,
    m.last_class,
    m.points_balance,
    mbp.account_linked_to_id,
    mbp.total_monthly_recurring_price,
    mbp.card_brand,
    mbp.card_last_four,
    mbp.card_exp_month,
    mbp.card_exp_year,
    ms.plan_id,
    ms.discount_ids,
    ms.item_id,
    ms.status       AS membership_status,
    ms.start_date   AS membership_start_date,
    ms.end_date     AS membership_end_date,
    ms.cancel_date  AS membership_cancel_date,
    ms.freeze_start_date,
    ms.freeze_end_date,
    ms.last_paid_date,
    ms.next_due_date,
    ms.total_price,
    mp.plan_name,
    mp.plan_type,
    mpp.price     AS base_cost,
    COALESCE(NOT mpp.is_active, false) AS on_outdated_price,
    mp.duration_amount,
    mp.duration_unit,
    gr.rank_id              AS rank_id,
    gr.main_name            AS rank_main_name,
    gr.sub_name             AS rank_sub_name,
    gr.image_url            AS rank_image_url,
    gr.color                AS rank_color,
    gr.classes_till_rankup  AS rank_classes_till_rankup
FROM member_billing_profile mbp
JOIN members m ON m.member_id = mbp.member_id
LEFT JOIN latest_memberships ms
    ON mbp.member_id = ms.member_id
    AND mbp.gym_id = ms.gym_id
LEFT JOIN membership_plans mp
    ON ms.plan_id = mp.plan_id
    AND ms.gym_id = mp.gym_id
LEFT JOIN membership_plan_prices mpp
    ON ms.price_id = mpp.price_id
    AND ms.gym_id = mpp.gym_id
LEFT JOIN gym_ranks gr
    ON m.current_rank_id = gr.rank_id
    AND m.gym_id = gr.gym_id
JOIN gyms g ON mbp.gym_id = g.gym_id
WHERE mbp.member_id IN (SELECT member_id FROM family_group)
ORDER BY
    CASE ms.status
        WHEN 'active' THEN 1
        WHEN 'frozen' THEN 2
        WHEN 'ended' THEN 3
        WHEN 'cancelled' THEN 4
    END ASC,
    CASE mp.plan_type
        WHEN 'recurring' THEN 1
        WHEN 'one_time' THEN 2
        WHEN 'trial' THEN 3
    END ASC
