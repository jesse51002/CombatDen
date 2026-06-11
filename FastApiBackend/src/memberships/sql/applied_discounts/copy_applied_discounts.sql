-- Reprice carry-over: copy the old membership's LIVE applications onto the
-- successor row. Applied-discount rows are append-only records — the old
-- rows stay pinned to the old membership untouched; the copies carry the
-- frozen value_id + end_date and start with no coupon (the next sync's
-- deterministic value→coupon resolution stamps them for the new line). The
-- live filter keeps a consumed `once` (end_date stamped <= today) from ever
-- being re-granted. :sync_status is 'not_added' for the real reprice (run
-- AFTER the old row is cancelled, so the single-LIVE-application custom
-- trigger admits the copy) and 'preview_add' for the reprice preview's
-- staged dry-run (deleted in the preview's cleanup). Runs on the caller's
-- session (no commit here).
INSERT INTO member_membership_applied_discounts_unfiltered
    (item_id, member_id, gym_id, value_id, end_date, stripe_sync_status)
SELECT
    CAST(:new_item_id AS UUID),
    member_id,
    gym_id,
    value_id,
    end_date,
    CAST(:sync_status AS stripe_sync_status)
FROM member_membership_applied_discounts_unfiltered
WHERE item_id = :old_item_id
  AND (end_date IS NULL OR end_date > CAST(:gym_today AS DATE))
  AND stripe_sync_status <> 'deleted'
RETURNING applied_discount_id
