-- Drop the materialized occurrence itself. member_attendance for this row is
-- already deleted (classes_undo_delete_attendance.sql ran first in the same
-- transaction), so no FK violation. Append-only RLS denies authenticated
-- DELETE; this runs at service_role.
DELETE FROM class_history
WHERE class_history_id = CAST(:class_history_id AS UUID)
