-- Raw class sign-ups (reservations) for the gym.
SELECT
    s.signup_id,
    s.gym_id,
    s.class_id,
    s.member_id,
    s.original_date,
    s.original_time,
    s.created_at
FROM class_signups s
WHERE s.gym_id = CAST(:gym_id AS UUID)
ORDER BY s.created_at ASC, s.signup_id ASC
