-- Retire the 'migrating' stripe_sync_status value. Nothing stages it anymore:
-- a reprice is cancel-old-row + insert-successor (the membership_reprice
-- task), never an in-place line move, so the transient migration state is
-- gone. Postgres cannot DROP an enum value, so the type is recreated and the
-- two consuming columns are retyped through text. Handwritten — `supabase db
-- diff` cannot express an enum-value removal. Mirrors
-- schemas/member_memberships.sql and
-- schemas/member_membership_applied_discounts.sql.

-- Safety data-fix: the state is transient, so no row should hold it; an
-- interrupted legacy migration's row is billing-active, which 'applied'
-- represents (the reconciler converges it).
UPDATE member_memberships_unfiltered
SET stripe_sync_status = 'applied'
WHERE stripe_sync_status = 'migrating';

-- Dependents on the column/type: the three views and the two restrictive
-- RLS policies that filter on the enum.
DROP VIEW member_memberships_status;
DROP VIEW member_memberships;
DROP VIEW member_membership_applied_discounts;
DROP POLICY "hide_incomplete_stripe_records" ON member_memberships_unfiltered;
DROP POLICY "hide_incomplete_stripe_records" ON member_membership_applied_discounts_unfiltered;

ALTER TABLE member_memberships_unfiltered
    ALTER COLUMN stripe_sync_status DROP DEFAULT;
ALTER TABLE member_membership_applied_discounts_unfiltered
    ALTER COLUMN stripe_sync_status DROP DEFAULT;

-- The CHECK existed only to rule 'migrating' out of applied-discount rows —
-- the value itself is gone now.
ALTER TABLE member_membership_applied_discounts_unfiltered
    DROP CONSTRAINT applied_discount_sync_status_not_migrating;

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

ALTER TABLE member_memberships_unfiltered
    ALTER COLUMN stripe_sync_status SET DEFAULT 'not_added';
ALTER TABLE member_membership_applied_discounts_unfiltered
    ALTER COLUMN stripe_sync_status SET DEFAULT 'not_added';

-- Recreate the policies verbatim (access_rules/member_memberships.sql and
-- access_rules/member_membership_applied_discounts.sql).
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

-- Recreate the views verbatim (schemas files), with security_invoker.
CREATE VIEW member_memberships
WITH (security_invoker = true)
AS
SELECT * FROM member_memberships_unfiltered
WHERE stripe_item_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

ALTER VIEW member_memberships SET (security_invoker = true);

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
JOIN members mbp
    ON mbp.member_id = mm.member_id
JOIN members freeze_owner
    ON freeze_owner.member_id = COALESCE(mbp.account_linked_to_id, mbp.member_id);

ALTER VIEW member_memberships_status SET (security_invoker = true);

CREATE VIEW member_membership_applied_discounts
WITH (security_invoker = true)
AS
SELECT * FROM member_membership_applied_discounts_unfiltered
WHERE stripe_coupon_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

ALTER VIEW member_membership_applied_discounts SET (security_invoker = true);

-- Re-establish the views' privileges. Default privileges may grant the app
-- roles ALL on new relations, so the write REVOKEs from the access rules are
-- re-applied (the simple views are auto-updatable; writes must stay
-- service_role-only).
GRANT SELECT ON member_memberships TO authenticated, service_role;
GRANT SELECT ON member_memberships_status TO authenticated, service_role;
GRANT SELECT ON member_membership_applied_discounts TO authenticated, service_role;
REVOKE INSERT, UPDATE ON member_memberships FROM authenticated;
REVOKE INSERT, UPDATE ON member_membership_applied_discounts FROM authenticated;
