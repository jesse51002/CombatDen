-- Hand-authored migration.
-- Adds an approval-status lifecycle to member_reward_redemptions:
--   reward_redemption_status enum ('pending' | 'approved' | 'rejected')
--   status column (NOT NULL DEFAULT 'pending')
--   decided_at column (TIMESTAMPTZ, nullable — set when admin approves/rejects)
-- Backfills all existing rows to 'approved' (historical redemptions are
-- completed, not pending).

CREATE TYPE reward_redemption_status AS ENUM (
    'pending',
    'approved',
    'rejected'
);

ALTER TABLE member_reward_redemptions
    ADD COLUMN status reward_redemption_status NOT NULL DEFAULT 'pending',
    ADD COLUMN decided_at TIMESTAMPTZ;

-- Historical redemptions are completed grants, not pending requests.
UPDATE member_reward_redemptions
    SET status = 'approved';
