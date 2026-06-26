WITH target_profile AS (
    SELECT mbp.member_id, mbp.gym_id
    FROM member_billing_profile mbp
    WHERE mbp.member_id = :member_id
),
family_group AS (
    -- The viewed member, plus every member they PAY FOR
    -- (member_memberships.paid_by_member_id), so the payer math behind the
    -- overview line + the "pays for" list can see those funded memberships.
    -- Authorization rosters (who may pay for whom) are separate junction reads.
    SELECT t.member_id
    FROM target_profile t
    UNION
    SELECT DISTINCT mm.member_id
    FROM member_memberships_status mm
    JOIN target_profile t ON t.gym_id = mm.gym_id
    WHERE mm.paid_by_member_id = :member_id
),
-- Collapse RECURRING reprice history to the current row (one card per plan),
-- but keep EACH one_time / trial pack DISTINCT by item_id — stacked or
-- separately-bought packs on the same plan are different memberships and must
-- each surface, not collapse to the most recent. So the DISTINCT-ON key is the
-- plan for recurring, the item for one_time / trial (CASE: NULL vs item_id).
latest_memberships AS (
    SELECT DISTINCT ON (
        mms.member_id, mms.gym_id, mms.plan_id,
        CASE WHEN mp.plan_type = 'recurring'
             THEN NULL::uuid ELSE mms.item_id END
    ) mms.*
    FROM member_memberships_status mms
    JOIN membership_plans mp
        ON mp.plan_id = mms.plan_id AND mp.gym_id = mms.gym_id
    ORDER BY mms.member_id, mms.gym_id, mms.plan_id,
             CASE WHEN mp.plan_type = 'recurring'
                  THEN NULL::uuid ELSE mms.item_id END,
             mms.start_date DESC, mms.created_at DESC
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
    mbp.total_monthly_recurring_price,
    mbp.card_brand,
    mbp.card_last_four,
    mbp.card_exp_month,
    mbp.card_exp_year,
    ms.plan_id,
    COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
            'applied_discount_id', ad.applied_discount_id,
            'item_id', ad.item_id,
            'member_id', ad.member_id,
            'gym_id', ad.gym_id,
            'value_id', ad.value_id,
            'discount_id', d.discount_id,
            'discount_name', d.discount_name,
            'discount_type', d.discount_type,
            'percentage_off', v.percentage_off,
            'dollar_off', v.dollar_off,
            'end_date', ad.end_date
         ) ORDER BY ad.created_at)
         FROM member_membership_applied_discounts ad
         JOIN gym_discount_values v ON v.value_id = ad.value_id
         JOIN gym_discounts d ON d.discount_id = v.discount_id
         WHERE ad.item_id = ms.item_id
           AND (ad.end_date IS NULL OR ad.end_date >= CURRENT_DATE)),
        '[]'::jsonb
    ) AS applied_discounts,
    ms.item_id,
    ms.paid_by_member_id,
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
    (
        SELECT ap.price
        FROM membership_plan_prices ap
        WHERE ap.plan_id = ms.plan_id
          AND ap.gym_id = ms.gym_id
          AND ap.is_active = TRUE
    ) AS current_active_price,
    mp.duration_amount,
    mp.duration_unit,
    gr.rank_id              AS rank_id,
    gr.main_name            AS rank_main_name,
    gr.sub_name             AS rank_sub_name,
    gr.image_url            AS rank_image_url,
    gr.color                AS rank_color,
    gr.classes_till_rankup  AS rank_classes_till_rankup,
    (now() AT TIME ZONE g.timezone)::date AS gym_today
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
    END ASC,
    -- Tiebreaker within a plan-type group (the one-time / trial packs):
    -- newest start first, so stacked class packs are date-ordered, not
    -- left to heap order.
    ms.start_date DESC
