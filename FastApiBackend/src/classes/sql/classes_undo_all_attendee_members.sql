-- Every member with attendance on one occurrence (pre-delete snapshot), to
-- drive the per-attendee check-in reverser loop when the occurrence is
-- un-occurred / future-wiped. Keyed by the occurrence's full identity
-- (class_id, original_date, original_time) -- a same-day sibling slot's
-- attendees are never swept in. NOT joined to memberships, so a
-- no-membership (NULL-attribution) attendee — who still earned points — is
-- included; the reverser reads each member's own attribution from the row it
-- deletes.
SELECT DISTINCT member_id
FROM member_attendance
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date = CAST(:original_date AS DATE)
  AND original_time = CAST(:original_time AS TIME)
