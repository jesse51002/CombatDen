-- Applied-discount snapshots, slimmed to the version model. One row = one
-- discount frozen onto one membership (item_id / Stripe item) at apply-time,
-- referencing the exact immutable gym_discount_values version (value_id) it was
-- applied at. The discount's values are reached via
-- value_id -> gym_discount_values -> gym_discounts; the value_id IS the
-- provenance / version tag, so we can always prove which version a member is on.
--
-- Applying a discount writes a row (INSERT); removing it deletes the row
-- (DELETE); the user never edits a row. The sync (service_role) legitimately
-- writes back two outcome fields: stripe_coupon_id (the coupon it resolved for
-- the consolidated line) and end_date (resolved from the version's lifetime at
-- apply, and stamped when a `once` discount is consumed).
--
-- Any discount is applied this way, including a `linked` (family) discount — a
-- linked applied row references the linked discount's value version like any
-- other; the membership/family flow supplies the linked discount's id.
--
-- Stripe-gated table: stripe_coupon_id is written by the sync, so this follows
-- the unfiltered-base-table + filtered-view pattern — the view exposes only rows
-- whose coupon has been written back, hiding a just-applied discount until the
-- sync resolves its coupon.
CREATE TABLE member_membership_applied_discounts_unfiltered (
    applied_discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    item_id UUID NOT NULL,
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL
        CONSTRAINT fk_applied_membership_discount_gym REFERENCES gyms(gym_id),

    -- The immutable discount value version this snapshot is frozen to (the
    -- version tag / provenance). Its row carries the percent/dollar, mode, and
    -- lifetime; the parent gym_discounts carries name + type.
    value_id UUID NOT NULL,

    -- Resolved absolute end for this application (from the version's duration
    -- span or explicit end_date, computed at apply); also stamped by the sync
    -- when a `once` discount is consumed. NULL = no end / pending consumption.
    end_date DATE,

    -- SYSTEM writeback: the coupon the sync resolved for this snapshot's
    -- consolidated line; for `once` snapshots this is the consumption-tracking
    -- handle (present on the subscription = pending, absent = consumed).
    stripe_coupon_id VARCHAR,

    -- Stripe-sync confirmation (service_role writeback). The `stripe_sync_status`
    -- enum is declared in member_memberships.sql (the earliest-loaded consumer).
    -- 'not_added' (default) = pending: the row is asking the sync to resolve its
    -- coupon; the sync stamps `applied` once it does. `preview_*` reserved for
    -- preview-staging. The enum is shared with member_memberships, but `migrating`
    -- is a membership-only state (a subscription item being re-pointed to a new
    -- price) — it never applies to an applied-discount row, so the CHECK rules it
    -- out even though the shared enum technically allows the value.
    stripe_sync_status stripe_sync_status NOT NULL DEFAULT 'not_added'
        CONSTRAINT applied_discount_sync_status_not_migrating
        CHECK (stripe_sync_status <> 'migrating'),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (applied_discount_id),

    -- The membership this discount is frozen onto must belong to the same gym.
    CONSTRAINT fk_applied_discount_membership_gym
        FOREIGN KEY (item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id),

    -- The member must match the membership's member (and the gym).
    CONSTRAINT fk_applied_discount_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    -- The value version must belong to the same gym (so we can't point at a
    -- version from another gym).
    CONSTRAINT fk_applied_discount_value_gym
        FOREIGN KEY (value_id, gym_id)
        REFERENCES gym_discount_values_unfiltered (value_id, gym_id)
);

CREATE INDEX idx_member_membership_applied_discounts_item
    ON member_membership_applied_discounts_unfiltered (item_id);

CREATE INDEX idx_member_membership_applied_discounts_member
    ON member_membership_applied_discounts_unfiltered (member_id, gym_id);

CREATE INDEX idx_member_membership_applied_discounts_value
    ON member_membership_applied_discounts_unfiltered (value_id);

-- A `custom` discount is SINGLE-OWNER: applied to at most one LIVE membership
-- at a time. A second applied row referencing any value of a custom discount
-- is rejected at the DB while an existing application is still live — not
-- ended (end_date unset or in the future) AND its membership not yet cancelled
-- (cancel_date unset or in the future). This keeps the reprice carry-over
-- legal: the reprice task cancels the old membership effective today, then
-- copies its live applications onto the successor row — the old application no
-- longer counts as live, while applying the same custom to a second live
-- membership still fails. Together with the single-value trigger on
-- gym_discount_values this keeps the custom lifecycle explicit (mint -> apply
-- -> follow the membership's successor chain -> archive on cleanup).
CREATE FUNCTION prevent_custom_discount_reapplication()
RETURNS TRIGGER AS $$
DECLARE
    v_discount_id UUID;
    v_discount_type VARCHAR;
    v_today DATE;
BEGIN
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

CREATE TRIGGER trg_custom_discount_single_application
    BEFORE INSERT ON member_membership_applied_discounts_unfiltered
    FOR EACH ROW
    EXECUTE FUNCTION prevent_custom_discount_reapplication();

-- View: gate on BOTH the Stripe coupon id and the sync-status enum. A row with
-- no `stripe_coupon_id` has no coupon resolved yet (not valid to surface), and
-- the sync-status hides `not_added` (pending) and `preview_*` (dry-run staging),
-- so clients only see synced applied discounts. The two conditions are kept in
-- lockstep with the `hide_incomplete_stripe_records` RLS policy
-- (`access_rules/member_membership_applied_discounts.sql`) so they can't drift.
CREATE VIEW member_membership_applied_discounts
WITH (security_invoker = true)
AS
SELECT * FROM member_membership_applied_discounts_unfiltered
WHERE stripe_coupon_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_membership_applied_discounts SET (security_invoker = true);
