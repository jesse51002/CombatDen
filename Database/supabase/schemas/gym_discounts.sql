-- Gym discount presets — now regular-only (preset | custom) and coupon-free.
--
-- Linked (family) discounts no longer live as a preset entity: a family
-- discount is just a snapshot row on the applied-discounts table marked
-- `linked`, carrying the plan + level + entered amount (entered in the CRM at
-- apply-time). So this table drops membership_plan_id, linked_discount_num, the
-- enforce_linked_discount_sequence triggers, and chk_linked_discount_fields.
--
-- Coupons also leave the preset layer: no stripe_coupon_id here anymore. The
-- sync computes each consolidated line's effective coupon at sync-time and
-- writes the resolved coupon back onto the applied snapshots. Presets store
-- pure intent and are valid the moment they are inserted, so there is no
-- Stripe gate — the view is now an unfiltered passthrough and gym staff author
-- presets directly (see access_rules/gym_discounts.sql).
--
-- Lifetime spec: discount_mode (once | ongoing) PLUS, for ongoing, an end set
-- by EITHER a duration span (duration_amount + duration_unit ∈ day/week/month)
-- OR an explicit end_date — exactly one, never both (CHECK); neither = forever.
-- At apply-time the snapshot's absolute end_date is computed from this spec. We
-- enforce the cutoff ourselves, so day/week/month all work (Stripe coupons stay
-- once/forever).

-- Discount lifetime mode. Also consumed by member_membership_applied_discounts,
-- which loads later — declared here (the earliest-loaded consumer).
CREATE TYPE discount_mode AS ENUM ('once', 'ongoing');

-- Duration span unit for an ongoing discount's lifetime. Dedicated to discounts
-- (day/week/month) — distinct from membership_plans' duration_unit
-- (week/month/year), which is a different domain.
CREATE TYPE discount_duration_unit AS ENUM ('day', 'week', 'month');

CREATE TABLE gym_discounts_unfiltered (
    discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_discount_gym REFERENCES gyms(gym_id),
    discount_name VARCHAR NOT NULL CHECK (discount_name <> ''),
    discount_type VARCHAR NOT NULL CHECK (discount_type IN ('preset', 'custom')),
    percentage_off FLOAT CHECK (percentage_off > 0 AND percentage_off <= 100),
    dollar_off INTEGER CHECK (dollar_off > 0),

    -- Lifetime spec.
    discount_mode discount_mode NOT NULL,
    duration_amount INTEGER CHECK (duration_amount > 0),
    duration_unit discount_duration_unit,
    end_date DATE,

    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (discount_id),
    UNIQUE (discount_id, gym_id),
    CHECK (num_nonnulls(percentage_off, dollar_off) = 1),

    -- duration_amount and duration_unit travel together.
    CONSTRAINT chk_discount_duration_pair CHECK (
        (duration_amount IS NULL) = (duration_unit IS NULL)
    ),

    -- Lifetime is at most one of: a duration span OR an explicit end_date.
    -- Never both. Neither = forever.
    CONSTRAINT chk_discount_lifetime_exclusive CHECK (
        NOT (duration_amount IS NOT NULL AND end_date IS NOT NULL)
    )
);

-- View: passthrough of the base table. Presets are valid on insert (no Stripe
-- gate now that coupons are computed at sync), so there is no filter. Kept as a
-- view so existing `gym_discounts` consumers (PostgREST endpoints, reads)
-- continue to resolve.
CREATE VIEW gym_discounts
WITH (security_invoker = true)
AS
SELECT * FROM gym_discounts_unfiltered;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW gym_discounts SET (security_invoker = true);
