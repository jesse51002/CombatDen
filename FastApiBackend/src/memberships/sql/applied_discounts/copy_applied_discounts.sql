-- Reprice carry-over: copy the old membership's LIVE applications onto the
-- successor row. Applied-discount rows are append-only records — the old
-- rows stay pinned to the old membership untouched; the copies start
-- 'not_added' with no coupon (the next sync's deterministic value→coupon
-- resolution stamps them for the new line). The live filter keeps a consumed
-- `once` (end_date stamped <= today) from ever being re-granted; carried
-- end_dates ride along unchanged. Runs inside the reprice transaction AFTER
-- the old row is cancelled (the caller's session, no commit here) so the
-- single-LIVE-application custom-discount trigger admits the copy.
INSERT INTO member_membership_applied_discounts_unfiltered
    (item_id, member_id, gym_id, value_id, end_date)
SELECT
    CAST(:new_item_id AS UUID),
    member_id,
    gym_id,
    value_id,
    end_date
FROM member_membership_applied_discounts_unfiltered
WHERE item_id = :old_item_id
  AND (end_date IS NULL OR end_date > CAST(:gym_today AS DATE))
  AND stripe_sync_status <> 'deleted'
