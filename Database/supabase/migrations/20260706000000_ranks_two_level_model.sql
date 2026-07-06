-- Hand-authored migration.
-- Rank System v2 — the two-level model: ONE gym_ranks row per MAIN rank, a
-- per-gym sub_rank_type (stripes | div), members pinned to a leaf via
-- current_rank_id + current_sub_index, and belt image_url back as a
-- user-writable field. rank_presets is re-keyed to a dedicated
-- rank_preset_kind enum and reshaped to the same main-row shape, and the
-- now-orphan gym_type Postgres enum is dropped.
--
-- CLEAN PRE-PROD RESEED: the founder DROPs/reseeds after applying this — no
-- production rows exist, so the NOT NULL DEFAULT column adds are safe and no
-- backfill of sub_rank_count / current_sub_index is needed.
--
--   1. CREATE TYPE sub_rank_type ('stripes', 'div').
--   2. gyms: add sub_rank_type NOT NULL DEFAULT 'stripes'.
--   3. members: add current_sub_index (nullable; >= 0 when set).
--   4. gym_ranks: drop the old (gym_id, main, sub) composite unique; rename
--      main_name -> name and classes_till_rankup -> classes_to_next_major;
--      drop sub_name / sub_rank_num_order / color; add sub_rank_count +
--      sub_rank_image_overrides; add the new (gym_id, main_rank_num_order)
--      unique; re-apply the client-write REVOKEs for the new column set.
--   5. rank_presets: drop the table + the now-orphan gym_type enum, then
--      recreate it keyed on the new rank_preset_kind enum with the main-row
--      shape, and re-emit its RLS/SELECT policy.
--
-- Mirrors schemas/gyms.sql, schemas/gym_ranks.sql, schemas/members.sql,
-- schemas/rank_presets.sql and access_rules/gym_ranks.sql +
-- access_rules/rank_presets.sql (end state). The old composite-unique name
-- (gym_ranks_gym_id_main_rank_num_order_sub_rank_num_order_key) was confirmed
-- against the initial migration 20260603202943_start.sql; if applying against
-- a hand-modified DB, verify with \d gym_ranks first. No views reference
-- gym_ranks or rank_presets; nothing to FK to rank_presets.

-- ── 1. sub_rank_type enum ───────────────────────────────────────────────────

CREATE TYPE sub_rank_type AS ENUM ('stripes', 'div');

-- ── 2. gyms: per-gym sub-rank style ─────────────────────────────────────────

ALTER TABLE gyms
    ADD COLUMN sub_rank_type sub_rank_type NOT NULL DEFAULT 'stripes';

-- ── 3. members: leaf position within the current main rank ──────────────────

ALTER TABLE members
    ADD COLUMN current_sub_index INTEGER
        CHECK (current_sub_index IS NULL OR current_sub_index >= 0);

-- ── 4. gym_ranks: one row per MAIN rank ─────────────────────────────────────

-- Drop the old (gym_id, main_rank_num_order, sub_rank_num_order) composite
-- unique (its backing index goes with the constraint). The members FK
-- fk_member_current_rank references (rank_id, gym_id) — backed by
-- gym_ranks_rank_id_gym_id_key, which is untouched.
ALTER TABLE gym_ranks
    DROP CONSTRAINT gym_ranks_gym_id_main_rank_num_order_sub_rank_num_order_key;

-- Rename to the main-row vocabulary (the column CHECK constraints follow the
-- rename automatically).
ALTER TABLE gym_ranks RENAME COLUMN main_name TO name;
ALTER TABLE gym_ranks RENAME COLUMN classes_till_rankup TO classes_to_next_major;

-- Drop the per-sub-row columns + color (dropping a column drops its CHECK).
ALTER TABLE gym_ranks DROP COLUMN sub_name;
ALTER TABLE gym_ranks DROP COLUMN sub_rank_num_order;
ALTER TABLE gym_ranks DROP COLUMN color;

-- Add the sub-rank count + persist-only per-sub image override map.
ALTER TABLE gym_ranks
    ADD COLUMN sub_rank_count INTEGER NOT NULL DEFAULT 0
        CHECK (sub_rank_count >= 0);
ALTER TABLE gym_ranks
    ADD COLUMN sub_rank_image_overrides JSONB NOT NULL DEFAULT '{}'::jsonb;

-- New ladder-position unique: one main rank per position per gym.
ALTER TABLE gym_ranks
    ADD CONSTRAINT gym_ranks_gym_id_main_rank_num_order_key
        UNIQUE (gym_id, main_rank_num_order);

-- Client-write REVOKEs for the new column set. main_rank_num_order is
-- reorder-only (two-phase reorder path); image_url is now user-writable so it
-- is deliberately NOT revoked. (The old sub_rank_num_order REVOKE disappeared
-- with the dropped column; the rank_id/gym_id/created_at REVOKEs from
-- 20260603202943_start.sql are re-stated here for the full end-state set.)
REVOKE UPDATE (rank_id, gym_id, created_at, main_rank_num_order)
    ON TABLE gym_ranks FROM authenticated;

-- ── 5. rank_presets: re-key to rank_preset_kind + main-row shape ────────────

-- rank_presets is static reference data with no inbound FKs and no dependent
-- views, and it is the last consumer of the gym_type Postgres enum, so both
-- can be dropped outright and rebuilt.
DROP TABLE rank_presets;
DROP TYPE gym_type;

CREATE TYPE rank_preset_kind AS ENUM ('bjj_belts', 'bjj_belts_stripes', 'flat');

CREATE TABLE rank_presets (
    preset_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    preset_kind rank_preset_kind NOT NULL,
    main_rank_num_order INTEGER NOT NULL CHECK (main_rank_num_order >= 0),
    name VARCHAR NOT NULL CHECK (name <> ''),
    image_url VARCHAR,
    classes_to_next_major INTEGER NOT NULL CHECK (classes_to_next_major >= 0),
    sub_rank_count INTEGER NOT NULL DEFAULT 0 CHECK (sub_rank_count >= 0),
    -- The gym sub_rank_type this preset implies; NULL when it has no
    -- sub-ranks. from_preset copies MAX(implied_sub_rank_type) onto the gym.
    implied_sub_rank_type sub_rank_type,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (preset_id),
    UNIQUE (preset_kind, main_rank_num_order)
);

-- Re-emit rank_presets RLS (copied from access_rules/rank_presets.sql).
ALTER TABLE rank_presets ENABLE ROW LEVEL SECURITY;

-- Static reference data — anyone authenticated can read so onboarding
-- flows can list available presets.
CREATE POLICY "Authenticated can view rank presets"
    ON rank_presets
    FOR SELECT
    TO authenticated
    USING (true);

-- Writes go through service_role only (this is curated reference data).

-- Re-grant the role privileges. Supabase's platform default privileges grant
-- ALL to anon/authenticated/service_role on every table (RLS then governs),
-- but a raw DROP TABLE + CREATE TABLE in a migration does NOT re-inherit them
-- (only fresh-created tables do), so the recreated rank_presets would have no
-- grants and the service_role seed 42501s ("permission denied for table
-- rank_presets"). Re-grant explicitly to restore the original posture.
GRANT ALL ON TABLE rank_presets TO anon;
GRANT ALL ON TABLE rank_presets TO authenticated;
GRANT ALL ON TABLE rank_presets TO service_role;
