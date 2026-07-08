-- Remove one class_attended loyalty-feed row for a removed check-in. The
-- activity log carries no occurrence timestamp (member_activities has no
-- created_at), so when a member attended this class more than once the rows are
-- indistinguishable -- this deletes a single matching row (best effort), keeping
-- the feed roughly in step with the reverted attendance + points. A no-op when
-- no matching activity exists.
DELETE FROM member_activities
WHERE activity_id = (
    SELECT activity_id
    FROM member_activities
    WHERE member_id = CAST(:m AS UUID)
      AND gym_id = CAST(:g AS UUID)
      AND activity_type = CAST(:activity_type AS member_activity_type)
      AND activity_info ->> 'class_id' = :class_id
    LIMIT 1
)
