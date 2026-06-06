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
    -- NULL = pending: the row is asking the sync to add it; the sync stamps
    -- `applied` once Stripe confirms (and `deleted` on removal). `preview_*`
    -- reserved for preview-staging.
    stripe_sync_status stripe_sync_status,

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

-- View: only exposes snapshots whose Stripe coupon has been written back by the
-- sync, so half-synced rows (a just-applied discount before the sync resolves
-- its coupon) are hidden from clients.
CREATE VIEW member_membership_applied_discounts
WITH (security_invoker = true)
AS
SELECT * FROM member_membership_applied_discounts_unfiltered
WHERE stripe_coupon_id IS NOT NULL;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_membership_applied_discounts SET (security_invoker = true);
