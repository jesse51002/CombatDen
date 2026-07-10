-- Record a "class_attended" activity for the member, in the same transaction as
-- the attendance INSERT + points award. activity_info is a JSONB snapshot of the
-- class + points awarded (class_id, class_name, points).
INSERT INTO member_activities (member_id, gym_id, activity_type, activity_info)
VALUES (
    CAST(:m AS UUID),
    CAST(:g AS UUID),
    CAST(:activity_type AS member_activity_type),
    CAST(:info AS JSONB)
)
