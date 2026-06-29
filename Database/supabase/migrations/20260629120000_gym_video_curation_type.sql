-- HAND-AUTHORED migration. Collapses the prior split (rejection_type /
-- acceptance_type / reject_reason / accept_reason) into a single unified pair:
--
--   curation_type  (gym_video_curation_type NOT NULL DEFAULT 'automatic')
--                  — how the row's CURRENT scan_status was set.
--   curation_reason TEXT
--                  — the owner's latest manual-curation reason; scan_status
--                    already says keep vs reject so one field covers both.
--
-- Starting state (only migrations 20260627020000 + 20260628130000 applied):
--   rejection_type  gym_video_rejection_type (NOT renamed yet)
--   reject_reason   TEXT
--   rejected_at     TIMESTAMPTZ
--   accept_reason   TEXT
--   curated_at      TIMESTAMPTZ
--   constraint rejection_type_when_rejected
--   NO acceptance_type column

-- ============================================================
-- 1. Rename the enum (gym_video_rejection_type → gym_video_curation_type)
-- ============================================================
ALTER TYPE gym_video_rejection_type RENAME TO gym_video_curation_type;

-- ============================================================
-- 2. Rename the column (rejection_type → curation_type)
-- ============================================================
ALTER TABLE gym_video_feed RENAME COLUMN rejection_type TO curation_type;

-- ============================================================
-- 3. Back-fill curation_type for rows that were NULL (accepted rows
--    that pre-date any manual curation — placed by the scan/import).
--    A non-NULL curated_at means the row was manually touched at some
--    point; NULL curated_at means automatic only.
-- ============================================================
UPDATE gym_video_feed
SET curation_type =
    CASE WHEN curated_at IS NOT NULL THEN 'manual'::gym_video_curation_type
         ELSE 'automatic'::gym_video_curation_type END
WHERE curation_type IS NULL;

-- ============================================================
-- 3b. Unconditionally promote any manually-touched row to 'manual'.
--     A row that had rejection_type='automatic' before step 2 may have
--     been manually kept later (curated_at IS NOT NULL), making its true
--     curation_type 'manual'. Step 3's WHERE curation_type IS NULL skips
--     those rows because the rename already set a non-NULL value. This
--     pass fixes them regardless of the value left by the rename.
-- ============================================================
UPDATE gym_video_feed
SET curation_type = 'manual'::gym_video_curation_type
WHERE curated_at IS NOT NULL;

-- ============================================================
-- 4. Lock curation_type: default 'automatic', NOT NULL
-- ============================================================
ALTER TABLE gym_video_feed ALTER COLUMN curation_type SET DEFAULT 'automatic';
ALTER TABLE gym_video_feed ALTER COLUMN curation_type SET NOT NULL;

-- ============================================================
-- 5. Drop the now-redundant rejected-only constraint
-- ============================================================
ALTER TABLE gym_video_feed DROP CONSTRAINT rejection_type_when_rejected;

-- ============================================================
-- 6. Add unified curation_reason column
-- ============================================================
ALTER TABLE gym_video_feed ADD COLUMN curation_reason TEXT;

-- ============================================================
-- 7. Back-fill curation_reason: take reject_reason when rejected,
--    accept_reason when accepted
-- ============================================================
UPDATE gym_video_feed
SET curation_reason =
    CASE WHEN scan_status = 'rejected' THEN reject_reason ELSE accept_reason END;

-- ============================================================
-- 8. Drop the split reason columns
-- ============================================================
ALTER TABLE gym_video_feed DROP COLUMN reject_reason;
ALTER TABLE gym_video_feed DROP COLUMN accept_reason;
