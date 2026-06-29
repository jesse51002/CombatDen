-- Total attendance still recorded against one membership (per item_id), used by
-- the auto-end reversal: after deleting the un-occurred class's attendance, a
-- trial / one_time pack that is now below its capacity gets its end_date
-- cleared. A trial / one_time pack is consumed over its single lifetime window,
-- so the lifetime COUNT(*) is the depletion signal (no billing-cycle window).
SELECT COUNT(*) AS attendance_count
FROM member_attendance
WHERE item_id = CAST(:item_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
