-- §8 schema deltas applied on top of §7 (20260616052748_paid_by_member_id.sql).
-- Combines the three unapplied draft migrations (20260611100000,
-- 20260611101500, 20260611103000) into one clean migration that builds on
-- §7's final schema (member_memberships + member_memberships_status already
-- carry paid_by_member_id; linked_account_no_stripe already dropped).
--
-- Sections:
--   A. price_id immutability trigger (and stripe_item_id guard without the
--      'migrating' carve-out)
--   B. Custom-discount single-LIVE-application relaxation
--   C. Retire the 'migrating' stripe_sync_status enum value (type recreate)
--   D. tasks + task_items tables, enums, and access rules
--
-- Hand-authored — `supabase db diff` cannot express enum-value removals and
-- strips security_invoker off recreated views (a tenant-leak RLS bypass).
-- Mirrors schemas/member_memberships.sql, schemas/member_membership_applied_
-- discounts.sql, schemas/tasks.sql, schemas/task_items.sql, and the
-- corresponding access_rules/ files.

-- ============================================================
-- A. Immutability triggers on member_memberships_unfiltered
-- ============================================================

-- stripe_item_id: immutable once set, no exceptions. Replaces the earlier
-- version of this function that permitted a 'migrating' carve-out — nothing
-- re-stamps a line id anymore (a reprice is cancel-old-row + insert-new-row).
CREATE OR REPLACE FUNCTION prevent_stripe_item_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stripe_item_id IS NOT NULL
       AND NEW.stripe_item_id IS DISTINCT FROM OLD.stripe_item_id THEN
        RAISE EXCEPTION 'stripe_item_id cannot be changed once set'
            USING CONSTRAINT = 'stripe_item_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- price_id: immutable, even at service-role. A reprice is a NEW membership
-- row at the new price (the membership_reprice task), never an in-place edit.
CREATE OR REPLACE FUNCTION prevent_price_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.price_id IS DISTINCT FROM OLD.price_id THEN
        RAISE EXCEPTION 'price_id cannot be changed after creation'
            USING CONSTRAINT = 'price_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_price_id_overwrite
    BEFORE UPDATE OF price_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_price_id_overwrite();

-- Recurring INSERT gates: skip + ignore preview-staged rows; cancelled-today
-- counts as inactive so a successor inserted the same day passes.
CREATE OR REPLACE FUNCTION check_recurring_no_active_memberships()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
    v_active_count INTEGER;
    v_today DATE;
BEGIN
    IF NEW.stripe_sync_status = 'preview_add' THEN
        RETURN NEW;
    END IF;

    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT (now() AT TIME ZONE g.timezone)::date INTO v_today
        FROM gyms g WHERE g.gym_id = NEW.gym_id;

        SELECT COUNT(*) INTO v_active_count
        FROM member_memberships_unfiltered mm
        WHERE mm.member_id = NEW.member_id
          AND mm.gym_id = NEW.gym_id
          AND mm.plan_id = NEW.plan_id
          AND mm.item_id <> NEW.item_id
          AND mm.stripe_sync_status <> 'preview_add'
          AND (mm.cancel_date IS NULL OR mm.cancel_date > v_today)
          AND (mm.end_date IS NULL OR mm.end_date > v_today);

        IF v_active_count > 0 THEN
            RAISE EXCEPTION 'cannot add recurring membership while an active membership on the same plan exists'
                USING CONSTRAINT = 'recurring_requires_no_active';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_recurring_no_overlapping_daterange()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.stripe_sync_status = 'preview_add' THEN
        RETURN NEW;
    END IF;

    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        IF EXISTS (
            SELECT 1
            FROM member_memberships_unfiltered mm
            WHERE mm.member_id = NEW.member_id
              AND mm.gym_id = NEW.gym_id
              AND mm.plan_id = NEW.plan_id
              AND mm.item_id <> NEW.item_id
              AND mm.stripe_sync_status <> 'preview_add'
              AND daterange(mm.start_date, mm.cancel_date, '[)')
               && daterange(NEW.start_date, NEW.cancel_date, '[)')
        ) THEN
            RAISE EXCEPTION 'recurring membership overlaps an existing membership on the same plan'
                USING CONSTRAINT = 'recurring_no_overlapping_daterange';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Chronological start: equality passes (same-day successor); only a
-- back-dated insert is rejected.
CREATE OR REPLACE FUNCTION check_recurring_chronological_start_date()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
    v_max_start_date DATE;
BEGIN
    IF NEW.stripe_sync_status = 'preview_add' THEN
        RETURN NEW;
    END IF;

    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT MAX(mm.start_date) INTO v_max_start_date
        FROM member_memberships_unfiltered mm
        WHERE mm.member_id = NEW.member_id
          AND mm.gym_id = NEW.gym_id
          AND mm.plan_id = NEW.plan_id
          AND mm.item_id <> NEW.item_id
          AND mm.stripe_sync_status <> 'preview_add';

        IF v_max_start_date IS NOT NULL AND NEW.start_date < v_max_start_date THEN
            RAISE EXCEPTION 'start_date must be on or after % (latest existing start_date for this plan)', v_max_start_date
                USING CONSTRAINT = 'recurring_chronological_start_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- B. Custom-discount: single LIVE application (relaxation)
-- ============================================================
-- Replaces the function installed by 20260610120000_custom_discount_single_use
-- (which rejected any second application, ever) with a version that only
-- rejects a second application while an EXISTING one is still live — the
-- reprice carry-over (old membership already cancelled effective today) passes;
-- a second application to a live membership still fails. The trigger
-- (trg_custom_discount_single_application) already exists and still fires on
-- BEFORE INSERT; only the function body changes.
CREATE OR REPLACE FUNCTION prevent_custom_discount_reapplication()
RETURNS TRIGGER AS $$
DECLARE
    v_discount_id UUID;
    v_discount_type VARCHAR;
    v_today DATE;
BEGIN
    IF NEW.stripe_sync_status = 'preview_add' THEN
        RETURN NEW;
    END IF;

    SELECT v.discount_id, d.discount_type
      INTO v_discount_id, v_discount_type
      FROM gym_discount_values_unfiltered v
      JOIN gym_discounts_unfiltered d ON d.discount_id = v.discount_id
     WHERE v.value_id = NEW.value_id;

    IF v_discount_type = 'custom' THEN
        SELECT (now() AT TIME ZONE g.timezone)::date INTO v_today
        FROM gyms g WHERE g.gym_id = NEW.gym_id;

        IF EXISTS (
            SELECT 1
              FROM member_membership_applied_discounts_unfiltered a
              JOIN gym_discount_values_unfiltered v2
                ON v2.value_id = a.value_id
              JOIN member_memberships_unfiltered mm
                ON mm.item_id = a.item_id
             WHERE v2.discount_id = v_discount_id
               AND a.stripe_sync_status <> 'preview_add'
               AND (a.end_date IS NULL OR a.end_date > v_today)
               AND (mm.cancel_date IS NULL OR mm.cancel_date > v_today)
        ) THEN
            RAISE EXCEPTION
                'custom discount % is single-use and already applied to a live membership',
                v_discount_id;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- C. Retire the 'migrating' stripe_sync_status enum value
-- ============================================================
-- Postgres cannot DROP an enum value, so the type is recreated and the two
-- consuming columns are retyped through text. The views and restrictive RLS
-- policies that reference the type must be dropped first and recreated after
-- in their §7 forms (with paid_by_member_id, security_invoker = true).

-- Safety data-fix: 'migrating' was a transient state — no row should hold it;
-- an interrupted legacy migration's row is billing-active, which 'applied'
-- represents (the reconciler converges it).
UPDATE member_memberships_unfiltered
    SET stripe_sync_status = 'applied'
    WHERE stripe_sync_status = 'migrating';

UPDATE member_membership_applied_discounts_unfiltered
    SET stripe_sync_status = 'applied'
    WHERE stripe_sync_status = 'migrating';

-- Drop dependents in reverse dependency order:
--   member_memberships_status depends on member_memberships,
--   member_memberships depends on member_memberships_unfiltered (type column),
--   member_membership_applied_discounts depends on
--     member_membership_applied_discounts_unfiltered (type column).
DROP VIEW IF EXISTS member_memberships_status;
DROP VIEW IF EXISTS member_memberships;
DROP VIEW IF EXISTS member_membership_applied_discounts;

DROP POLICY IF EXISTS "hide_incomplete_stripe_records" ON member_memberships_unfiltered;
DROP POLICY IF EXISTS "hide_incomplete_stripe_records" ON member_membership_applied_discounts_unfiltered;

-- Drop defaults before altering column type (Postgres requires it).
ALTER TABLE member_memberships_unfiltered
    ALTER COLUMN stripe_sync_status DROP DEFAULT;
ALTER TABLE member_membership_applied_discounts_unfiltered
    ALTER COLUMN stripe_sync_status DROP DEFAULT;

-- The CHECK existed only to rule 'migrating' out of applied-discount rows —
-- the value itself is gone now, so the constraint is moot.
ALTER TABLE member_membership_applied_discounts_unfiltered
    DROP CONSTRAINT IF EXISTS applied_discount_sync_status_not_migrating;

-- Rename old type, create the new one (without 'migrating'), retype columns,
-- then drop the old type.
ALTER TYPE stripe_sync_status RENAME TO stripe_sync_status_old;

CREATE TYPE stripe_sync_status AS ENUM (
    'not_added',
    'applied',
    'deleted',
    'preview_add',
    'preview_remove'
);

ALTER TABLE member_memberships_unfiltered
    ALTER COLUMN stripe_sync_status TYPE stripe_sync_status
    USING stripe_sync_status::text::stripe_sync_status;

ALTER TABLE member_membership_applied_discounts_unfiltered
    ALTER COLUMN stripe_sync_status TYPE stripe_sync_status
    USING stripe_sync_status::text::stripe_sync_status;

DROP TYPE stripe_sync_status_old;

-- Restore column defaults.
ALTER TABLE member_memberships_unfiltered
    ALTER COLUMN stripe_sync_status SET DEFAULT 'not_added';
ALTER TABLE member_membership_applied_discounts_unfiltered
    ALTER COLUMN stripe_sync_status SET DEFAULT 'not_added';

-- Recreate the restrictive RLS policies (verbatim from access_rules/).
CREATE POLICY "hide_incomplete_stripe_records"
    ON member_memberships_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (
        stripe_item_id IS NOT NULL
        AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove')
    );

CREATE POLICY "hide_incomplete_stripe_records"
    ON member_membership_applied_discounts_unfiltered
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (
        stripe_coupon_id IS NOT NULL
        AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove')
    );

-- Recreate member_memberships in its §7 form (with paid_by_member_id,
-- security_invoker = true). Mirrors schemas/member_memberships.sql.
CREATE VIEW member_memberships
WITH (security_invoker = true)
AS
SELECT * FROM member_memberships_unfiltered
WHERE stripe_item_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

ALTER VIEW member_memberships SET (security_invoker = true);

-- Recreate member_memberships_status in its §7 form: freeze is per PAYER
-- (paid_by_member_id), security_invoker = true. Mirrors
-- schemas/member_memberships.sql.
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

ALTER VIEW member_memberships_status SET (security_invoker = true);

-- Recreate member_membership_applied_discounts. Mirrors
-- schemas/member_membership_applied_discounts.sql.
CREATE VIEW member_membership_applied_discounts
WITH (security_invoker = true)
AS
SELECT * FROM member_membership_applied_discounts_unfiltered
WHERE stripe_coupon_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

ALTER VIEW member_membership_applied_discounts SET (security_invoker = true);

-- Re-establish view privileges (default privileges may grant app roles ALL
-- on new relations; the write REVOKEs from access_rules/ are re-applied).
GRANT SELECT ON member_memberships TO authenticated, service_role;
GRANT SELECT ON member_memberships_status TO authenticated, service_role;
GRANT SELECT ON member_membership_applied_discounts TO authenticated, service_role;
REVOKE INSERT, UPDATE ON member_memberships FROM authenticated;
REVOKE INSERT, UPDATE ON member_membership_applied_discounts FROM authenticated;

-- ============================================================
-- D. tasks + task_items tables, enums, and access rules
-- ============================================================
-- Mirrors schemas/tasks.sql, schemas/task_items.sql, access_rules/tasks.sql,
-- access_rules/task_items.sql.

CREATE TYPE task_type AS ENUM (
    'membership_reprice'
);

CREATE TYPE task_status AS ENUM (
    'pending',
    'running',
    'completed',
    'failed'
);

CREATE TABLE tasks (
    task_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_task_gym REFERENCES gyms(gym_id),
    task_type task_type NOT NULL,
    status task_status NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    PRIMARY KEY (task_id),
    UNIQUE (task_id, gym_id)
);

CREATE INDEX idx_tasks_gym_status ON tasks (gym_id, status);
CREATE INDEX idx_tasks_unfinished ON tasks (status)
    WHERE status IN ('pending', 'running');

CREATE TABLE task_items (
    task_item_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    task_id UUID NOT NULL CONSTRAINT fk_task_item_task REFERENCES tasks(task_id),
    gym_id UUID NOT NULL CONSTRAINT fk_task_item_gym REFERENCES gyms(gym_id),
    member_id UUID NOT NULL,
    status task_status NOT NULL DEFAULT 'pending',
    attempt_count INTEGER NOT NULL DEFAULT 0
        CONSTRAINT task_item_attempts_non_negative CHECK (attempt_count >= 0),
    error_message TEXT,
    old_item_id UUID,
    new_item_id UUID,
    target_price_id UUID
        CONSTRAINT fk_task_item_target_price
        REFERENCES membership_plan_prices_unfiltered(price_id),
    prorate BOOLEAN,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    PRIMARY KEY (task_item_id),
    CONSTRAINT fk_task_item_task_gym
        FOREIGN KEY (task_id, gym_id)
        REFERENCES tasks (task_id, gym_id),
    CONSTRAINT fk_task_item_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    CONSTRAINT fk_task_item_old_membership_gym
        FOREIGN KEY (old_item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id),
    CONSTRAINT fk_task_item_new_membership_gym
        FOREIGN KEY (new_item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id)
);

CREATE INDEX idx_task_items_task ON task_items (task_id);
CREATE INDEX idx_task_items_old_membership ON task_items (old_item_id)
    WHERE old_item_id IS NOT NULL;
CREATE INDEX idx_task_items_new_membership ON task_items (new_item_id)
    WHERE new_item_id IS NOT NULL;

-- Access rules for tasks (mirrors access_rules/tasks.sql)
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym staff can view tasks"
    ON tasks
    FOR SELECT
    USING (is_gym_admin_or_owner(tasks.gym_id));

REVOKE INSERT, UPDATE, DELETE ON TABLE tasks FROM authenticated;

-- Access rules for task_items (mirrors access_rules/task_items.sql)
ALTER TABLE task_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Gym staff can view task items"
    ON task_items
    FOR SELECT
    USING (is_gym_admin_or_owner(task_items.gym_id));

REVOKE INSERT, UPDATE, DELETE ON TABLE task_items FROM authenticated;
