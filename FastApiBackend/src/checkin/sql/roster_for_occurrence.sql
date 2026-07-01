-- Combined roster for one occurrence: everyone who signed up OR attended,
-- each flagged, ordered by name. Sign-ups come from class_signups keyed by
-- (class_id, occurrence_date); attendance comes from member_attendance
-- joined through the occurrence's class_history row, matched to the same
-- gym-local calendar day (the caller passes its UTC [day_start, day_end)
-- bounds, mirroring find_history_for_day.sql -- LIMIT 1 mirrors that same
-- lookup, since one class has at most one occurrence per gym-local day). A
-- member who is both signed up and attended appears ONCE, with both flags
-- true and the attendance fields populated; a signed-up-only member's
-- log_id/plan_id/item_id are NULL. gym_id scopes the read to the requesting
-- employee's gym.
WITH occurrence_history AS (
    SELECT class_history_id
    FROM class_history
    WHERE class_id = CAST(:class_id AS UUID)
      AND occurred_at >= CAST(:day_start AS TIMESTAMPTZ)
      AND occurred_at <  CAST(:day_end AS TIMESTAMPTZ)
    ORDER BY occurred_at
    LIMIT 1
),
roster_members AS (
    SELECT member_id
    FROM class_signups
    WHERE class_id = CAST(:class_id AS UUID)
      AND gym_id = CAST(:gym_id AS UUID)
      AND occurrence_date = CAST(:occurrence_date AS DATE)
    UNION
    SELECT member_id
    FROM member_attendance
    WHERE gym_id = CAST(:gym_id AS UUID)
      AND class_history_id IN (SELECT class_history_id FROM occurrence_history)
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
    AND cs.occurrence_date = CAST(:occurrence_date AS DATE)
LEFT JOIN member_attendance ma
    ON  ma.member_id = rm.member_id
    AND ma.gym_id = CAST(:gym_id AS UUID)
    AND ma.class_history_id IN (SELECT class_history_id FROM occurrence_history)
ORDER BY m.first_name, m.last_name
