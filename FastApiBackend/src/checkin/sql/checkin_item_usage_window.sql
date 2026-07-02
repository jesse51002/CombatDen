-- Attendance drawn against ONE membership (item_id) inside an explicit
-- billing window — the historical-cycle recount for a RETRO check-in whose
-- occurrence falls in a past cycle (CycleCountsService derives the window by
-- stepping the current anchor back by the plan's duration). Same
-- date-vs-occurred_at comparison semantics as classes_all_memberships.sql's
-- current-window count, so present and past cycles count identically.
SELECT COUNT(*) AS classes_used
FROM member_attendance
WHERE item_id = CAST(:item_id AS UUID)
  AND occurred_at >= CAST(:window_start AS DATE)
  AND occurred_at <  CAST(:window_end AS DATE)
