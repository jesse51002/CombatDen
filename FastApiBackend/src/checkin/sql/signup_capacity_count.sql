-- Distinct members signed-up OR attended for one class occurrence -- the
-- capacity-reserving set. Sign-ups come from class_signups keyed by
-- (class_id, occurrence_date); attendance comes from member_attendance
-- joined through the occurrence's class_history row, matched to the same
-- gym-local calendar day (the caller passes its UTC [day_start, day_end)
-- bounds, mirroring find_history_for_day.sql, so a per-occurrence time
-- override still resolves to the same day). LIMIT 1 on the occurrence lookup
-- mirrors find_history_for_day.sql -- one class has at most one occurrence
-- per gym-local day. UNION dedupes a member counted both ways. Shared by the
-- sign-up create path's capacity check and the check-in capacity gate, so a
-- member already in this set (a prior sign-up, or a prior/walk-in check-in)
-- is never double-counted against the room.
WITH occurrence_history AS (
    SELECT class_history_id
    FROM class_history
    WHERE class_id = CAST(:class_id AS UUID)
      AND occurred_at >= CAST(:day_start AS TIMESTAMPTZ)
      AND occurred_at <  CAST(:day_end AS TIMESTAMPTZ)
    ORDER BY occurred_at
    LIMIT 1
)
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
