-- Clear an auto-end-on-depletion end_date after un-occurring a class drops a
-- trial / one_time pack back below its capacity. Keyed by item_id (the specific
-- pack that was charged) + member_id. Writes the base table (the
-- member_memberships view is REVOKE'd). NEVER touches members.points_balance or
-- member_activities -- points are never clawed back (and the points_balance >= 0
-- CHECK would abort a claw-back anyway). Setting end_date = NULL is allowed by
-- trg_recurring_no_end_date (NULL is the no-op branch) and end_date is not an
-- immutable column.
UPDATE member_memberships_unfiltered
SET end_date = NULL
WHERE item_id = CAST(:item_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
