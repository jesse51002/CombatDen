-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Switches gym staff (`gym_employees`) and member (`members`) identity
-- linkage from `user_id` (an `auth.users` FK) to VERIFIED EMAIL
-- (lower-cased) -- the new identity key for both tables. Also adds
-- `gym_employees.archived_at` (soft-archive: a revoked employee; rows are
-- never hard-deleted since the instructor + waiver-operator FKs reference
-- them) and replaces `chk_trainer_has_no_account` with
-- `chk_principal_has_email` (only a 'trainer' row may be email-less
-- instructor data; every login role -- owner/admin/front_desk -- must carry
-- an email).
--
-- Every RLS policy anywhere in the schema that matched a row via
-- "<table>.user_id = auth.uid()" (a member's own row) or
-- "gym_employees.user_id = auth.uid()" (the employee bootstrap clause) is
-- rewritten to "lower(<table>.email) = lower(auth.jwt() ->> 'email')".
-- Postgres tracks a real (non-internal) catalog dependency from a policy's
-- USING/WITH CHECK expression -- and from a LANGUAGE SQL function's body --
-- onto every column it references, so EVERY one of those policies (there
-- are far more than just the two tables' own policies -- member ownership is
-- re-checked from a couple dozen other tables' RLS) and the two
-- SECURITY DEFINER helper functions must be redefined BEFORE the
-- `DROP COLUMN user_id` statements below, or the drop fails with
-- "cannot drop column user_id because other objects depend on it". This is
-- why this migration's ordering differs from a naive
-- "schema struct -> access rules" pass: all function/policy redefinitions
-- come first, then the structural column drops, then the one view that
-- depends on members.* via SELECT * (member_billing_profile) is dropped
-- before and recreated after.
--
-- Mirrors schemas/gyms.sql, members.sql and access_rules/gyms.sql,
-- members.sql, member_authorized_payers.sql, gym_ranks.sql,
-- member_reward_redemptions.sql, membership_plan_prices.sql,
-- member_invoice_applied_discounts.sql, video_rag.sql, gym_classes.sql,
-- member_activities.sql, gym_rewards.sql, member_waiver_signatures.sql,
-- class_instance_exceptions.sql, member_invoice_line_items.sql,
-- class_range_exceptions.sql, gym_video_feed.sql, class_signups.sql,
-- member_invoices.sql, gym_class_schedules.sql, gym_video_spec.sql,
-- member_attendance.sql, member_charges.sql,
-- member_membership_applied_discounts.sql, member_video_recs.sql,
-- member_memberships.sql, membership_plans.sql, video.sql, video_run.sql.
--
-- gym_video_feed.sql, gym_video_spec.sql, video.sql, video_rag.sql and
-- video_run.sql ALSO tighten their staff-SELECT arm from
-- is_gym_employee(...) to is_gym_admin_or_owner(...) as defense-in-depth
-- (every other is_gym_employee(...) staff-read policy in the schema --
-- schedule/roster/staff-list reads -- stays widened; not touched here).

-- ============================================================
-- 0. PRE-FLIGHT GUARDS -- run BEFORE any write statement.
--
--    Steps 5 below add `chk_principal_has_email` and the partial unique
--    index `unique_employee_email_gym`, but the OLD schema allowed both a
--    NULL email on an owner/admin row (identity was `user_id`) and repeated
--    emails within a gym. On a database holding either shape, the migration
--    would die PART-WAY -- after `DROP COLUMN user_id` -- with an opaque
--    "check constraint is violated by some row" / "could not create unique
--    index" error, leaving a half-migrated schema.
--
--    These two blocks are pure reads that RAISE before anything is applied,
--    naming the exact offending rows. There is deliberately NO backfill from
--    auth.users: the correct fix is a human setting the right email (or
--    demoting the row to 'trainer'), not a guess.
-- ============================================================

DO $$
DECLARE
    v_offenders TEXT;
BEGIN
    SELECT string_agg(
               format('employee_id=%s gym_id=%s employee_type=%s', e.employee_id, e.gym_id, e.employee_type),
               '; ' ORDER BY e.gym_id, e.employee_id
           )
      INTO v_offenders
      FROM gym_employees e
     WHERE e.employee_type <> 'trainer'
       AND e.email IS NULL;

    IF v_offenders IS NOT NULL THEN
        RAISE EXCEPTION
            'Cannot apply 20260711010001: login-carrying gym_employees row(s) have a NULL email, which chk_principal_has_email forbids. Offending rows: %',
            v_offenders
        USING HINT = 'Set the real (verified) email on every owner/admin/front_desk row, or demote a data-only row to employee_type = ''trainer'', then re-run.';
    END IF;
END $$;

DO $$
DECLARE
    v_dupes TEXT;
BEGIN
    SELECT string_agg(
               format('gym_id=%s email=%s (%s rows)', d.gym_id, d.email_lc, d.n),
               '; ' ORDER BY d.gym_id, d.email_lc
           )
      INTO v_dupes
      FROM (
        SELECT gym_id, lower(email) AS email_lc, count(*) AS n
          FROM gym_employees
         WHERE email IS NOT NULL
         GROUP BY gym_id, lower(email)
        HAVING count(*) > 1
      ) d;

    IF v_dupes IS NOT NULL THEN
        RAISE EXCEPTION
            'Cannot apply 20260711010001: duplicate (gym_id, lower(email)) pairs in gym_employees, which unique_employee_email_gym forbids. Offending pairs: %',
            v_dupes
        USING HINT = 'One employee row per email per gym -- archive or delete the extra rows (or give them their own email) before re-running.';
    END IF;
END $$;

-- ============================================================
-- 1. Normalize existing emails to lowercase (the new identity key)
-- ============================================================

UPDATE gym_employees SET email = lower(email) WHERE email IS NOT NULL;
UPDATE members SET email = lower(email) WHERE email IS NOT NULL;

-- ============================================================
-- 2. gym_employees.archived_at must exist BEFORE the helper functions
--    below reference it. Redefine is_gym_employee / is_gym_admin_or_owner
--    off email + archived_at instead of user_id -- this drops their
--    dependency on gym_employees.user_id before it's dropped in step 5.
-- ============================================================

ALTER TABLE gym_employees ADD COLUMN archived_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION is_gym_employee(p_gym_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = ''
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND lower(gym_employees.email) = lower(auth.jwt() ->> 'email')
        AND gym_employees.archived_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION is_gym_admin_or_owner(p_gym_id UUID)
RETURNS BOOLEAN
LANGUAGE sql SECURITY DEFINER SET search_path = ''
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.gym_employees
        WHERE gym_employees.gym_id = p_gym_id
        AND lower(gym_employees.email) = lower(auth.jwt() ->> 'email')
        AND gym_employees.archived_at IS NULL
        AND gym_employees.employee_type IN ('owner', 'admin')
    );
$$;
-- gym_has_owner(p_gym_id) is unchanged (still keys off employee_type only) --
-- not redefined here.

-- ============================================================
-- 3. Re-point every RLS policy that referenced <table>.user_id /
--    gym_employees.user_id to the email-based check.
-- ============================================================

-- --- gyms.sql / gym_employees ---

DROP POLICY IF EXISTS "Owners and admins can insert employees" ON gym_employees;
CREATE POLICY "Owners and admins can insert employees"
    ON gym_employees
    FOR INSERT
    TO authenticated
    WITH CHECK (
        is_gym_admin_or_owner(gym_employees.gym_id)
        OR (
            gym_employees.employee_type = 'owner'
            AND lower(gym_employees.email) = lower(auth.jwt() ->> 'email')
            AND NOT gym_has_owner(gym_employees.gym_id)
        )
    );

-- --- members.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view members" ON members;
CREATE POLICY "Users and gym staff can view members"
    ON members
    FOR SELECT
    USING (
        lower(members.email) = lower(auth.jwt() ->> 'email')
        OR is_gym_admin_or_owner(members.gym_id)
    );

DROP POLICY IF EXISTS "Users and gym staff can update members" ON members;
CREATE POLICY "Users and gym staff can update members"
    ON members
    FOR UPDATE
    USING (
        lower(members.email) = lower(auth.jwt() ->> 'email')
        OR is_gym_admin_or_owner(members.gym_id)
    )
    WITH CHECK (
        lower(members.email) = lower(auth.jwt() ->> 'email')
        OR is_gym_admin_or_owner(members.gym_id)
    );

-- --- member_authorized_payers.sql ---

DROP POLICY IF EXISTS "Gym staff and involved members can view authorized payers" ON member_authorized_payers;
CREATE POLICY "Gym staff and involved members can view authorized payers"
    ON member_authorized_payers
    FOR SELECT
    USING (
        is_gym_admin_or_owner(member_authorized_payers.gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE lower(members.email) = lower(auth.jwt() ->> 'email')
            AND members.member_id IN (
                member_authorized_payers.member_id,
                member_authorized_payers.payer_member_id
            )
        )
    );

-- --- gym_ranks.sql ---

DROP POLICY IF EXISTS "Members can view their gym's ranks" ON gym_ranks;
CREATE POLICY "Members can view their gym's ranks"
    ON gym_ranks
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_ranks.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- member_reward_redemptions.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view reward redemptions" ON member_reward_redemptions;
CREATE POLICY "Users and gym staff can view reward redemptions"
    ON member_reward_redemptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_reward_redemptions.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR is_gym_admin_or_owner(member_reward_redemptions.gym_id)
    );

DROP POLICY IF EXISTS "Members and gym staff can insert redemptions" ON member_reward_redemptions;
CREATE POLICY "Members and gym staff can insert redemptions"
    ON member_reward_redemptions
    FOR INSERT
    TO authenticated
    WITH CHECK (
        is_gym_admin_or_owner(member_reward_redemptions.gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_reward_redemptions.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
            AND members.gym_id = member_reward_redemptions.gym_id
        )
    );

-- --- membership_plan_prices.sql ---

DROP POLICY IF EXISTS "Members can view plan prices" ON membership_plan_prices_unfiltered;
CREATE POLICY "Members can view plan prices"
    ON membership_plan_prices_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = membership_plan_prices_unfiltered.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- member_invoice_applied_discounts.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view applied discounts" ON member_invoice_applied_discounts;
CREATE POLICY "Users and gym staff can view applied discounts"
    ON member_invoice_applied_discounts
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON lower(m.email) = lower(auth.jwt() ->> 'email')
            WHERE inv.invoice_id = member_invoice_applied_discounts.invoice_id
            AND (
                m.member_id = inv.paid_by_member_id
                OR inv.paid_for ? m.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoice_applied_discounts.gym_id)
    );

-- --- video_rag.sql (member arm + staff arm tightened to admin/owner) ---

DROP POLICY IF EXISTS "Read summaries for visible videos" ON video_rag;
CREATE POLICY "Read summaries for visible videos"
    ON video_rag
    FOR SELECT
    TO anon, authenticated
    USING (
        EXISTS (
            SELECT 1 FROM video
            WHERE video.video_id = video_rag.video_id
            AND (
                video.gym_id IS NULL
                OR is_gym_admin_or_owner(video.gym_id)
                OR EXISTS (
                    SELECT 1 FROM members
                    WHERE members.gym_id = video.gym_id
                    AND lower(members.email) = lower(auth.jwt() ->> 'email')
                )
            )
        )
    );

-- --- gym_classes.sql ---

DROP POLICY IF EXISTS "Members can view classes" ON gym_classes;
CREATE POLICY "Members can view classes"
    ON gym_classes
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_classes.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- member_activities.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view activities" ON member_activities;
CREATE POLICY "Users and gym staff can view activities"
    ON member_activities
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_activities.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR is_gym_admin_or_owner(member_activities.gym_id)
    );

-- --- gym_rewards.sql ---

DROP POLICY IF EXISTS "Members can view active rewards" ON gym_rewards;
CREATE POLICY "Members can view active rewards"
    ON gym_rewards
    FOR SELECT
    USING (
        is_active = true
        AND EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_rewards.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- member_waiver_signatures.sql ---

DROP POLICY IF EXISTS "Members and gym staff can view waiver signatures" ON member_waiver_signatures;
CREATE POLICY "Members and gym staff can view waiver signatures"
    ON member_waiver_signatures
    FOR SELECT
    USING (
        is_gym_admin_or_owner(member_waiver_signatures.gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_waiver_signatures.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- class_instance_exceptions.sql ---

DROP POLICY IF EXISTS "Members can view instance exceptions" ON class_instance_exceptions;
CREATE POLICY "Members can view instance exceptions"
    ON class_instance_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_instance_exceptions.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- member_invoice_line_items.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view invoice line items" ON member_invoice_line_items;
CREATE POLICY "Users and gym staff can view invoice line items"
    ON member_invoice_line_items
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON lower(m.email) = lower(auth.jwt() ->> 'email')
            WHERE inv.invoice_id = member_invoice_line_items.invoice_id
            AND (
                m.member_id = inv.paid_by_member_id
                OR inv.paid_for ? m.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoice_line_items.gym_id)
    );

-- --- class_range_exceptions.sql ---

DROP POLICY IF EXISTS "Members can view range exceptions" ON class_range_exceptions;
CREATE POLICY "Members can view range exceptions"
    ON class_range_exceptions
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = class_range_exceptions.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- gym_video_feed.sql (member arm + staff arm tightened to admin/owner) ---

DROP POLICY IF EXISTS "Gym employees can view video feed" ON gym_video_feed;
CREATE POLICY "Gym employees can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_video_feed.gym_id));

DROP POLICY IF EXISTS "Members can view video feed" ON gym_video_feed;
CREATE POLICY "Members can view video feed"
    ON gym_video_feed
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_feed.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- class_signups.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view class signups" ON class_signups;
CREATE POLICY "Users and gym staff can view class signups"
    ON class_signups
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = class_signups.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR is_gym_admin_or_owner(class_signups.gym_id)
    );

-- --- member_invoices.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view invoices" ON member_invoices;
CREATE POLICY "Users and gym staff can view invoices"
    ON member_invoices
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE lower(members.email) = lower(auth.jwt() ->> 'email')
            AND (
                members.member_id = member_invoices.paid_by_member_id
                OR member_invoices.paid_for ? members.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoices.gym_id)
    );

-- --- gym_class_schedules.sql ---

DROP POLICY IF EXISTS "Members can view class schedules" ON gym_class_schedules;
CREATE POLICY "Members can view class schedules"
    ON gym_class_schedules
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_class_schedules.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- gym_video_spec.sql (member arm + staff arm tightened to admin/owner) ---

DROP POLICY IF EXISTS "Gym employees can view video spec" ON gym_video_spec;
CREATE POLICY "Gym employees can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (is_gym_admin_or_owner(gym_video_spec.gym_id));

DROP POLICY IF EXISTS "Members can view video spec" ON gym_video_spec;
CREATE POLICY "Members can view video spec"
    ON gym_video_spec
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = gym_video_spec.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- member_attendance.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view attendance" ON member_attendance;
CREATE POLICY "Users and gym staff can view attendance"
    ON member_attendance
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_attendance.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR is_gym_admin_or_owner(member_attendance.gym_id)
    );

-- --- member_charges.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view charges" ON member_charges;
CREATE POLICY "Users and gym staff can view charges"
    ON member_charges
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_charges.paid_by_member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON lower(m.email) = lower(auth.jwt() ->> 'email')
            WHERE inv.invoice_id = member_charges.invoice_id
            AND inv.paid_for ? m.member_id::text
        )
        OR is_gym_admin_or_owner(member_charges.gym_id)
    );

-- --- member_membership_applied_discounts.sql ---

DROP POLICY IF EXISTS "Users and gym staff can view applied membership discounts" ON member_membership_applied_discounts_unfiltered;
CREATE POLICY "Users and gym staff can view applied membership discounts"
    ON member_membership_applied_discounts_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members m
            WHERE m.member_id = member_membership_applied_discounts_unfiltered.member_id
            AND lower(m.email) = lower(auth.jwt() ->> 'email')
        )
        OR is_gym_admin_or_owner(member_membership_applied_discounts_unfiltered.gym_id)
    );

-- --- member_video_recs.sql ---

DROP POLICY IF EXISTS "Members and gym staff can view rec history" ON member_video_recs;
CREATE POLICY "Members and gym staff can view rec history"
    ON member_video_recs
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_video_recs.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
        OR is_gym_admin_or_owner(member_video_recs.gym_id)
    );

-- --- member_memberships.sql ---

DROP POLICY IF EXISTS "Members can view own memberships" ON member_memberships_unfiltered;
CREATE POLICY "Members can view own memberships"
    ON member_memberships_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_memberships_unfiltered.member_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- membership_plans.sql ---

DROP POLICY IF EXISTS "Members can view gym plans" ON membership_plans_unfiltered;
CREATE POLICY "Members can view gym plans"
    ON membership_plans_unfiltered
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = membership_plans_unfiltered.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- video.sql (member arm + staff arm tightened to admin/owner) ---

DROP POLICY IF EXISTS "Read shared videos or own gym's custom videos" ON video;
CREATE POLICY "Read shared videos or own gym's custom videos"
    ON video
    FOR SELECT
    TO anon, authenticated
    USING (
        gym_id IS NULL
        OR is_gym_admin_or_owner(gym_id)
        OR EXISTS (
            SELECT 1 FROM members
            WHERE members.gym_id = video.gym_id
            AND lower(members.email) = lower(auth.jwt() ->> 'email')
        )
    );

-- --- video_run.sql (staff arm tightened to admin/owner; no member arm) ---

DROP POLICY IF EXISTS "Gym employees can view video runs" ON video_run;
CREATE POLICY "Gym employees can view video runs"
    ON video_run
    FOR SELECT
    USING (is_gym_admin_or_owner(video_run.gym_id));

-- ============================================================
-- 4. member_billing_profile is SELECT * FROM members -- it carries an
--    explicit dependency on every members column including user_id, so it
--    must be dropped before the DROP COLUMN in step 6, then recreated in
--    step 7.
-- ============================================================

DROP VIEW IF EXISTS member_billing_profile;

-- ============================================================
-- 5. gym_employees structural cleanup. chk_trainer_has_no_account and the
--    two user_id-involving indexes/constraints are dropped explicitly
--    (rather than relying on DROP COLUMN's implicit same-table cascade) to
--    keep the migration's intent legible. The UNIQUE(user_id, gym_id)
--    table constraint is named "gym_employees_user_id_gym_id_key" -- the
--    Postgres default name for that unnamed UNIQUE in the baseline
--    migration (confirmed: `grep gym_employees_user_id_gym_id_key
--    migrations/20260603202943_start.sql` -> both the index and the
--    constraint that reuses it are named exactly that).
-- ============================================================

ALTER TABLE gym_employees DROP CONSTRAINT chk_trainer_has_no_account;
DROP INDEX IF EXISTS unique_employee_user_gym;
ALTER TABLE gym_employees DROP CONSTRAINT gym_employees_user_id_gym_id_key;
ALTER TABLE gym_employees DROP COLUMN user_id; -- fk_employee_user auto-drops with it

ALTER TABLE gym_employees
    ADD CONSTRAINT chk_principal_has_email
        CHECK (employee_type = 'trainer' OR email IS NOT NULL);

CREATE UNIQUE INDEX unique_employee_email_gym
    ON gym_employees (gym_id, lower(email))
    WHERE email IS NOT NULL;

REVOKE UPDATE (archived_at) ON TABLE gym_employees FROM authenticated;

-- ============================================================
-- 6. members structural cleanup.
-- ============================================================

DROP TRIGGER trg_prevent_user_id_overwrite ON members;
DROP FUNCTION prevent_user_id_overwrite();
DROP INDEX IF EXISTS unique_member_user_gym;
ALTER TABLE members DROP COLUMN user_id; -- fk_member_user auto-drops with it

-- ============================================================
-- 7. Recreate member_billing_profile (dropped in step 4) exactly as in
--    schemas/members.sql -- it simply no longer surfaces user_id.
--    Recreating a view drops its grants, so re-grant.
-- ============================================================

CREATE VIEW member_billing_profile
WITH (security_invoker = true)
AS
SELECT * FROM members WHERE stripe_customer_id IS NOT NULL;

ALTER VIEW member_billing_profile SET (security_invoker = true);

GRANT SELECT ON member_billing_profile TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON member_billing_profile FROM authenticated;
