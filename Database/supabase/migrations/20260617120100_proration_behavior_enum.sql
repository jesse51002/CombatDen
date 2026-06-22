-- Replace task_items.prorate BOOLEAN with a typed proration_behavior enum, and
-- drop the now-dead member_memberships_unfiltered.prorate BOOLEAN column (it was
-- only ever written by the old reprice path, never read by the sync engine).
--
-- Sections:
--   A. Declare the proration_behavior enum (owner: task_items schema)
--   B. Convert task_items.prorate BOOLEAN → proration_behavior proration_behavior
--      (ADD column, backfill, DROP old column — no view dance needed here)
--   C. Drop member_memberships_unfiltered.prorate BOOLEAN
--      (requires dropping both dependent views first, then recreating them
--      exactly as declared in schemas/member_memberships.sql, security_invoker
--      preserved on both)
--
-- Hand-authored; `supabase db diff` strips security_invoker off recreated views.

-- ============================================================
-- A. Declare the proration_behavior enum
-- ============================================================

CREATE TYPE proration_behavior AS ENUM (
    'prorate_to_anchor',
    'no_charge'
);

-- ============================================================
-- B. Convert task_items.prorate BOOLEAN → proration_behavior
-- ============================================================
-- task_items has no views over it, so no view dance is required.

ALTER TABLE task_items ADD COLUMN proration_behavior proration_behavior;

UPDATE task_items
    SET proration_behavior = CASE
        WHEN prorate = true  THEN 'prorate_to_anchor'::proration_behavior
        WHEN prorate = false THEN 'no_charge'::proration_behavior
        ELSE NULL
    END;

ALTER TABLE task_items DROP COLUMN prorate;

-- ============================================================
-- C. Drop member_memberships_unfiltered.prorate BOOLEAN
-- ============================================================
-- Both views SELECT * / mm.* so they currently materialize the prorate column;
-- they must be dropped before the column can be removed.

DROP VIEW IF EXISTS member_memberships_status;
DROP VIEW IF EXISTS member_memberships;

ALTER TABLE member_memberships_unfiltered DROP COLUMN prorate;

-- Recreate member_memberships — verbatim from schemas/member_memberships.sql.
CREATE VIEW member_memberships
WITH (security_invoker = true)
AS
SELECT * FROM member_memberships_unfiltered
WHERE stripe_item_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

ALTER VIEW member_memberships SET (security_invoker = true);

-- Recreate member_memberships_status — verbatim from schemas/member_memberships.sql.
CREATE VIEW member_memberships_status
WITH (security_invoker = true)
AS
SELECT mm.*,
    freeze_owner.freeze_start_date,
    freeze_owner.freeze_end_date,
    CASE
        WHEN mm.cancel_date IS NOT NULL AND mm.cancel_date <= (now() AT TIME ZONE g.timezone)::date THEN 'cancelled'
        WHEN mm.end_date IS NOT NULL AND mm.end_date <= (now() AT TIME ZONE g.timezone)::date THEN 'ended'
        WHEN freeze_owner.freeze_start_date IS NOT NULL
             AND freeze_owner.freeze_end_date IS NOT NULL
             AND freeze_owner.freeze_start_date <= (now() AT TIME ZONE g.timezone)::date
             AND (now() AT TIME ZONE g.timezone)::date <= freeze_owner.freeze_end_date THEN 'frozen'
        ELSE 'active'
    END AS status
FROM member_memberships mm
JOIN gyms g ON g.gym_id = mm.gym_id
JOIN members freeze_owner
    ON freeze_owner.member_id = mm.paid_by_member_id;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_memberships_status SET (security_invoker = true);
