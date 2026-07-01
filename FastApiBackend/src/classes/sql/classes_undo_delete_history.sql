-- Drop the materialized occurrence itself. Every member_attendance row for this
-- occurrence is already deleted (the per-attendee check-in reverser ran first in
-- the same transaction), so no FK violation. Append-only RLS denies
-- authenticated DELETE; this runs at service_role.
DELETE FROM class_history
WHERE class_history_id = CAST(:class_history_id AS UUID)
