-- Raw member rows for the gym. Explicit column list: EXCLUDES the four RAG
-- video-taste profile columns (video_profile_summary / _embedding /
-- _embedding_model / _built_at) -- the embedding is machine-derived internal
-- state, never part of the gym's data export.
SELECT
    m.member_id,
    m.gym_id,
    m.created_at,
    m.last_class,
    m.first_name,
    m.last_name,
    m.email,
    m.points_balance,
    m.current_rank_id,
    m.current_sub_index,
    m.photo_url,
    m.phone,
    m.address,
    m.date_of_birth,
    m.emergency_contact_name,
    m.emergency_contact_phone,
    m.emergency_contact_email,
    m.freeze_start_date,
    m.freeze_end_date,
    m.stripe_customer_id,
    m.stripe_sub_id_month,
    m.stripe_payment_method_id,
    m.payment_type,
    m.card_brand,
    m.card_last_four,
    m.card_exp_month,
    m.card_exp_year,
    m.total_monthly_recurring_price
FROM members m
WHERE m.gym_id = CAST(:gym_id AS UUID)
ORDER BY m.created_at ASC, m.member_id ASC
