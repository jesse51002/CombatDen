-- Every member with attendance on one occurrence (pre-delete snapshot), for the
-- points/activity reversal when the occurrence is un-occurred. Unlike
-- classes_undo_find_attendees.sql this is NOT joined to memberships, so a
-- no-membership (NULL-attribution) attendee — who still earned points — is
-- included.
SELECT DISTINCT member_id
FROM member_attendance
WHERE class_history_id = CAST(:class_history_id AS UUID)
