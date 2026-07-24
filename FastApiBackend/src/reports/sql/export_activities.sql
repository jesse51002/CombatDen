-- Raw member activity feed for the gym. activity_info is a JSONB object
-- rendered as its text form.
SELECT
    act.activity_id,
    act.member_id,
    act.gym_id,
    act.activity_type,
    CAST(act.activity_info AS TEXT) AS activity_info,
    act.time
FROM member_activities act
WHERE act.gym_id = CAST(:gym_id AS UUID)
ORDER BY act.time ASC, act.activity_id ASC
