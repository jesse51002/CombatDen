-- Distinct members signed-up OR attended for one class occurrence -- the
-- capacity-reserving set, keyed directly by the occurrence's full identity
-- (class_id, original_date, original_time -- capacity pools are PER-SLOT, so
-- a same-day sibling occurrence's headcount never bleeds into this one's).
-- UNION dedupes a member counted both ways. Shared by the sign-up create
-- path's capacity check and the check-in capacity gate, so a member already
-- in this set (a prior sign-up, or a prior/walk-in check-in) is never
-- double-counted against the room.
SELECT member_id
FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
  AND original_date = CAST(:occurrence_date AS DATE)
  AND original_time = CAST(:occurrence_time AS TIME)
UNION
SELECT member_id
FROM member_attendance
WHERE class_id = CAST(:class_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
  AND original_date = CAST(:occurrence_date AS DATE)
  AND original_time = CAST(:occurrence_time AS TIME)
