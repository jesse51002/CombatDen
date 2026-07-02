-- Restore a trial / one_time pack's end_date after reversing a check-in drops
-- it back below its capacity: back to the plan's duration-derived expiry
-- (:end_date, computed by the reverser from start_date + duration) or NULL
-- for a pure class-count pack with no duration — never a blind NULL, which
-- would erase a duration pack's natural expiry. end_date is AUTOMATIC-only
-- by convention (depletion auto-end / purchase-stamped duration expiry); a
-- manual termination writes cancel_date, which this never touches — so a
-- manually-terminated pack can never be resurrected by attendance removal.
-- Keyed by item_id (the specific pack that was charged) + member_id. Writes
-- the base table (the member_memberships view is REVOKE'd). NEVER touches
-- members.points_balance or member_activities -- the points claw-back +
-- activity drop are separate steps. RETURNING item_id only when the value
-- actually changed (IS DISTINCT FROM), so the caller can report a real
-- un-end and stay silent on a no-op.
UPDATE member_memberships_unfiltered
SET end_date = CAST(:end_date AS DATE)
WHERE item_id = CAST(:item_id AS UUID)
  AND member_id = CAST(:member_id AS UUID)
  AND end_date IS DISTINCT FROM CAST(:end_date AS DATE)
RETURNING item_id
