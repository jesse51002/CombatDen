-- Best-effort removal of one class_attended loyalty-feed row for an un-occurred
-- attendee. member_activities has no timestamp, so when the member attended this
-- class more than once the rows are indistinguishable -- delete a single match.
DELETE FROM member_activities
WHERE activity_id = (
    SELECT activity_id
    FROM member_activities
    WHERE member_id = CAST(:m AS UUID)
      AND gym_id = CAST(:g AS UUID)
      AND activity_type = 'class_attended'
      AND activity_info ->> 'class_id' = :class_id
    LIMIT 1
)
