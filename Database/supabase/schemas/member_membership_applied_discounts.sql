-- Immutable applied-discount snapshots. One row = one discount frozen onto one
-- membership (item_id / Stripe item) at apply-time. Applying a discount writes
-- a frozen snapshot row; editing or deleting the source preset never touches
-- existing rows (predictability — a member's billing changes only via an
-- explicit add/remove on that member's specific membership). To change a
-- discount the user removes the row (DELETE) and adds a different one (INSERT);
-- the user never edits a row. The sync (service_role) legitimately writes back
-- two outcome fields: stripe_coupon_id (the coupon it resolved for the line)
-- and end_date (stamped when a `once` discount is consumed). Everything else is
-- a snapshot of the preset's intent at the moment of application.
--
-- Stripe-gated table: stripe_coupon_id is written by the sync, so this follows
-- the unfiltered-base-table + filtered-view pattern. The view exposes only rows
-- whose stripe_coupon_id has been written back, so a just-applied discount
-- becomes visible to clients once the sync resolves and writes its coupon.
--
-- The discount_mode enum is declared in gym_discounts.sql (the earliest-loaded
-- file that consumes it — the preset also stores discount_mode).
CREATE TABLE member_membership_applied_discounts_unfiltered (
    applied_discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    item_id UUID NOT NULL,
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL
        CONSTRAINT fk_applied_membership_discount_gym REFERENCES gyms(gym_id),

    discount_type VARCHAR NOT NULL
        CHECK (discount_type IN ('preset', 'custom', 'linked')),

    -- Provenance for regular (preset/custom) discounts: the gym_discounts
    -- preset this snapshot was copied from (enables future auto-update). NULL
    -- for linked discounts (no preset to read).
    source_discount_id UUID,

    -- Linked discounts carry the plan they derive from and the level/tier
    -- instead of a source preset.
    linked_discount_planid UUID,
    linked_discount_num INTEGER CHECK (linked_discount_num > 0),

    -- Snapshot of the preset's intent at apply-time.
    discount_name VARCHAR NOT NULL CHECK (discount_name <> ''),
    percentage_off FLOAT CHECK (percentage_off > 0 AND percentage_off <= 100),
    dollar_off INTEGER CHECK (dollar_off > 0),
    discount_mode discount_mode NOT NULL,

    -- Resolved absolute end (from the preset's duration span or explicit
    -- end_date, computed at apply); also stamped by the sync when a `once`
    -- discount is consumed. NULL = no end (forever) / pending consumption.
    end_date DATE,

    -- SYSTEM writeback: the coupon the sync resolved for this snapshot's
    -- consolidated line; for `once` snapshots this is the consumption-tracking
    -- handle (present on the subscription = pending, absent = consumed).
    stripe_coupon_id VARCHAR,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (applied_discount_id),

    -- Exactly one of percentage_off / dollar_off is set.
    CONSTRAINT chk_applied_discount_value
        CHECK (num_nonnulls(percentage_off, dollar_off) = 1),

    -- Linked rows require the plan + level; regular rows require a source
    -- preset. (Linked rows carry no source_discount_id; regular rows carry no
    -- linked metadata.)
    CONSTRAINT chk_applied_discount_provenance CHECK (
        (discount_type = 'linked'
            AND linked_discount_planid IS NOT NULL
            AND linked_discount_num IS NOT NULL
            AND source_discount_id IS NULL)
        OR
        (discount_type <> 'linked'
            AND source_discount_id IS NOT NULL
            AND linked_discount_planid IS NULL
            AND linked_discount_num IS NULL)
    ),

    -- The membership this discount is frozen onto must belong to the same gym.
    CONSTRAINT fk_applied_discount_membership_gym
        FOREIGN KEY (item_id, gym_id)
        REFERENCES member_memberships_unfiltered (item_id, gym_id),

    -- The member must match the membership's member (and the gym).
    CONSTRAINT fk_applied_discount_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    -- Provenance FK to the source preset (composite with gym so we can't point
    -- at a preset from another gym). NULL source_discount_id (linked rows)
    -- skips enforcement under MATCH SIMPLE.
    CONSTRAINT fk_applied_discount_source_gym
        FOREIGN KEY (source_discount_id, gym_id)
        REFERENCES gym_discounts_unfiltered (discount_id, gym_id)
);

CREATE INDEX idx_member_membership_applied_discounts_item
    ON member_membership_applied_discounts_unfiltered (item_id);

CREATE INDEX idx_member_membership_applied_discounts_member
    ON member_membership_applied_discounts_unfiltered (member_id, gym_id);

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
