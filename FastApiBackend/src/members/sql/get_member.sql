SELECT
    member_id,
    gym_id,
    user_id,
    first_name,
    last_name,
    email,
    points_balance,
    last_class,
    trial_start_date,
    trial_end_date,
    fully_active_start_date,
    inactive_start_date,
    current_rank_id,
    created_at
FROM members
WHERE member_id = :member_id
