-- Auto-end a trial / one_time membership once its classes are depleted.
-- Keyed by item_id (the specific membership row that was charged) so a member
-- holding two memberships on the same plan only ends the one used. Writes the
-- base table (the member_memberships view is REVOKE'd). Recurring plans are
-- never auto-ended (also enforced by trg_recurring_no_end_date).
UPDATE member_memberships_unfiltered
SET end_date = :end_date
WHERE item_id = :item_id
  AND member_id = :member_id
