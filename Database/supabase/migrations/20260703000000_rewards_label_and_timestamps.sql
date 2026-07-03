-- Hand-authored migration.
-- Two independent cleanups on the rewards domain:
--
-- 1) gym_rewards.amount_off is collapsed into price_label — the reward's
--    value label/badge (e.g. 'Free', '30% off') was two overlapping
--    free-text columns; price_label is kept as the single source, backfilled
--    from amount_off where price_label was not already set.
--
-- 2) member_reward_redemptions timestamps are renamed for clarity:
--      redeemed_at -> requested_at (when the member requested the redemption)
--      decided_at  -> resolved_at  (when staff approved/rejected it)
--    plus a CHECK constraint pairing resolved_at with status, mirroring
--    members.sql's freeze_dates_must_be_paired: resolved_at is NULL iff
--    status = 'pending'. The prior status migration
--    (20260628100000_reward_redemption_status.sql) backfilled existing rows
--    to 'approved' without setting decided_at, so those rows must be
--    backfilled here before the CHECK can be added.

UPDATE gym_rewards
SET price_label = COALESCE(price_label, amount_off);

ALTER TABLE gym_rewards
    DROP COLUMN amount_off;

ALTER TABLE member_reward_redemptions
    RENAME COLUMN redeemed_at TO requested_at;

ALTER TABLE member_reward_redemptions
    RENAME COLUMN decided_at TO resolved_at;

-- Backfill: rows already decided (approved/rejected) but left with a NULL
-- resolved_at by the earlier status migration must get one before the
-- pairing CHECK below can be added.
UPDATE member_reward_redemptions
SET resolved_at = requested_at
WHERE status <> 'pending' AND resolved_at IS NULL;

ALTER TABLE member_reward_redemptions
    ADD CONSTRAINT resolved_matches_status
        CHECK ((status = 'pending') = (resolved_at IS NULL));
