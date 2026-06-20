-- Split the billing rows' conflated `member_id` into `paid_by_member_id` (the
-- payer — whose Stripe customer/card was charged, or who staff recorded as
-- paying cash) and `paid_for` (a JSONB array of member_id strings — the
-- beneficiaries the bill was FOR). The split is lossless: every existing row
-- seeds paid_by_member_id = member_id and paid_for = [member_id]. Applies to
-- both member_invoices and member_charges. The four dependent SELECT RLS
-- policies are rebuilt to use the new columns; the old member_id column and its
-- composite FK + index are dropped last.
--
-- HAND-AUTHORED, not `supabase db diff` output: db diff strips security_invoker
-- off recreated views (a tenant-leak RLS bypass) and orders statements unsafely
-- on populated DBs. Mirrors schemas/member_invoices.sql,
-- schemas/member_charges.sql, and the four corresponding access_rules/ files.

-- ============================================================
-- 1. member_invoices: add paid_by_member_id + paid_for
-- ============================================================

ALTER TABLE "public"."member_invoices"
    ADD COLUMN "paid_by_member_id" uuid,
    ADD COLUMN "paid_for" jsonb NOT NULL DEFAULT '[]';

-- Lossless backfill: payer = old member_id; beneficiary list = [member_id].
UPDATE "public"."member_invoices"
    SET paid_by_member_id = member_id,
        paid_for = jsonb_build_array(member_id)
    WHERE paid_by_member_id IS NULL;

ALTER TABLE "public"."member_invoices"
    ALTER COLUMN "paid_by_member_id" SET NOT NULL;

ALTER TABLE "public"."member_invoices"
    ADD CONSTRAINT "fk_invoice_payer_gym"
        FOREIGN KEY (paid_by_member_id, gym_id)
        REFERENCES "public"."members" (member_id, gym_id)
        NOT VALID;
ALTER TABLE "public"."member_invoices"
    VALIDATE CONSTRAINT "fk_invoice_payer_gym";

CREATE INDEX "idx_invoices_payer_gym_time"
    ON "public"."member_invoices" (paid_by_member_id, gym_id, invoice_time DESC);

CREATE INDEX "idx_invoices_paid_for"
    ON "public"."member_invoices" USING GIN (paid_for);

-- ============================================================
-- 2. member_charges: add paid_by_member_id
-- ============================================================

ALTER TABLE "public"."member_charges"
    ADD COLUMN "paid_by_member_id" uuid;

-- Lossless backfill: payer = old member_id.
UPDATE "public"."member_charges"
    SET paid_by_member_id = member_id
    WHERE paid_by_member_id IS NULL;

ALTER TABLE "public"."member_charges"
    ALTER COLUMN "paid_by_member_id" SET NOT NULL;

ALTER TABLE "public"."member_charges"
    ADD CONSTRAINT "fk_charge_payer_gym"
        FOREIGN KEY (paid_by_member_id, gym_id)
        REFERENCES "public"."members" (member_id, gym_id)
        NOT VALID;
ALTER TABLE "public"."member_charges"
    VALIDATE CONSTRAINT "fk_charge_payer_gym";

CREATE INDEX "idx_charges_payer_gym_time"
    ON "public"."member_charges" (paid_by_member_id, gym_id, charge_time DESC);

-- ============================================================
-- 3. Rebuild the four SELECT RLS policies
-- ============================================================
-- The new columns exist on both tables now. Drop the old policies (which
-- reference member_id) and recreate them verbatim from access_rules/.
-- This must happen BEFORE member_id is dropped (step 4), because the
-- line_items / applied_discounts policies reference inv.paid_by_member_id
-- and inv.paid_for via a join to member_invoices.

DROP POLICY IF EXISTS "Users and gym staff can view invoices" ON "public"."member_invoices";
CREATE POLICY "Users and gym staff can view invoices"
    ON "public"."member_invoices"
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.user_id = auth.uid()
            AND (
                members.member_id = member_invoices.paid_by_member_id
                OR member_invoices.paid_for ? members.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoices.gym_id)
    );

DROP POLICY IF EXISTS "Users and gym staff can view charges" ON "public"."member_charges";
CREATE POLICY "Users and gym staff can view charges"
    ON "public"."member_charges"
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM members
            WHERE members.member_id = member_charges.paid_by_member_id
            AND members.user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON m.user_id = auth.uid()
            WHERE inv.invoice_id = member_charges.invoice_id
            AND inv.paid_for ? m.member_id::text
        )
        OR is_gym_admin_or_owner(member_charges.gym_id)
    );

DROP POLICY IF EXISTS "Users and gym staff can view invoice line items" ON "public"."member_invoice_line_items";
CREATE POLICY "Users and gym staff can view invoice line items"
    ON "public"."member_invoice_line_items"
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON m.user_id = auth.uid()
            WHERE inv.invoice_id = member_invoice_line_items.invoice_id
            AND (
                m.member_id = inv.paid_by_member_id
                OR inv.paid_for ? m.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoice_line_items.gym_id)
    );

DROP POLICY IF EXISTS "Users and gym staff can view applied discounts" ON "public"."member_invoice_applied_discounts";
CREATE POLICY "Users and gym staff can view applied discounts"
    ON "public"."member_invoice_applied_discounts"
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM member_invoices inv
            JOIN members m ON m.user_id = auth.uid()
            WHERE inv.invoice_id = member_invoice_applied_discounts.invoice_id
            AND (
                m.member_id = inv.paid_by_member_id
                OR inv.paid_for ? m.member_id::text
            )
        )
        OR is_gym_admin_or_owner(member_invoice_applied_discounts.gym_id)
    );

-- ============================================================
-- 4. Drop the old member_id artifacts
-- ============================================================
-- Composite FKs first (they reference member_id), then the btree indexes,
-- then the column itself.

ALTER TABLE "public"."member_invoices"
    DROP CONSTRAINT "fk_invoice_member_gym";

DROP INDEX IF EXISTS "public"."idx_invoices_member_gym_time";

ALTER TABLE "public"."member_invoices"
    DROP COLUMN "member_id";

ALTER TABLE "public"."member_charges"
    DROP CONSTRAINT "fk_charge_member_gym";

DROP INDEX IF EXISTS "public"."idx_charges_member_gym_time";

ALTER TABLE "public"."member_charges"
    DROP COLUMN "member_id";
