-- Combined roster for one occurrence: everyone who signed up OR attended,
-- each flagged, ordered by name. Keyed directly by the occurrence's
-- identity (class_id, original_date) -- no day-bounds join needed. A member who is both signed up and attended appears ONCE,
-- with both flags true and the attendance fields populated; a
-- signed-up-only member's log_id/plan_id/item_id are NULL. gym_id scopes
-- the read to the requesting employee's gym.
WITH roster_members AS (
    SELECT member_id
    FROM class_signups
    WHERE class_id = CAST(:class_id AS UUID)
      AND gym_id = CAST(:gym_id AS UUID)
      AND original_date = CAST(:occurrence_date AS DATE)
    UNION
    SELECT member_id
    FROM member_attendance
    WHERE class_id = CAST(:class_id AS UUID)
      AND gym_id = CAST(:gym_id AS UUID)
      AND original_date = CAST(:occurrence_date AS DATE)
)
SELECT
    m.member_id,
    m.first_name || ' ' || m.last_name AS full_name,
    (cs.signup_id IS NOT NULL) AS signed_up,
    (ma.log_id IS NOT NULL) AS attended,
    ma.log_id,
    ma.plan_id,
    ma.item_id
FROM roster_members rm
JOIN members m
    ON  m.member_id = rm.member_id
    AND m.gym_id = CAST(:gym_id AS UUID)
LEFT JOIN class_signups cs
    ON  cs.class_id = CAST(:class_id AS UUID)
    AND cs.member_id = rm.member_id
    AND cs.original_date = CAST(:occurrence_date AS DATE)
LEFT JOIN member_attendance ma
    ON  ma.member_id = rm.member_id
    AND ma.class_id = CAST(:class_id AS UUID)
    AND ma.original_date = CAST(:occurrence_date AS DATE)
ORDER BY m.first_name, m.last_name
