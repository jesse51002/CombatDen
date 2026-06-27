-- Versioned, immutable discount VALUES. Mirrors membership_plan_prices: a
-- gym_discounts identity owns one or more value versions. Editing a discount's
-- value never mutates a row — it inserts a NEW active version and deactivates
-- the old one, leaving a permanent paper trail. Applied snapshots reference an
-- immutable value_id, so a member's discount is frozen to the exact version it
-- was applied at; to prove where a discount came from you point at its value_id.
--
-- TRULY IMMUTABLE + service_role-write-only, exactly like membership_plan_prices:
-- clients never INSERT/UPDATE/DELETE a value row. The backend (service_role)
-- inserts a new version and flips the prior one's is_active; a value row's
-- columns are never mutated and versions are never deleted (permanent paper
-- trail). No Stripe column (coupons are computed at sync and written onto the
-- applied snapshot), so there is no Stripe gate. See
-- access_rules/gym_discount_values.sql.
--
-- The discount_duration_unit enum is declared here (the earliest-loaded
-- consumer): gym_discounts is identity-only and the applied snapshots reach a
-- discount's value (percent/dollar + lifetime) via value_id -> gym_discount_values.
--
-- Duration span unit for a discount's lifetime. Dedicated to discounts —
-- distinct from membership_plans' duration_unit (week/month/year), a different
-- domain. `cycle` is plan-relative: one cycle = the membership's plan billing
-- period, resolved to an absolute end_date at apply-time (1 cycle on a monthly
-- plan -> +1 month). It is how a single-invoice ("just the next cycle")
-- discount is expressed now that there is no separate once mode.
CREATE TYPE discount_duration_unit AS ENUM ('day', 'week', 'month', 'cycle');

CREATE TABLE gym_discount_values_unfiltered (
    value_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    discount_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_discount_value_gym REFERENCES gyms(gym_id),

    percentage_off FLOAT CHECK (percentage_off > 0 AND percentage_off <= 100),
    dollar_off INTEGER CHECK (dollar_off > 0),

    -- Lifetime spec: an end set by EITHER a duration span (duration_amount +
    -- duration_unit, where `cycle` is plan-relative) OR an explicit end_date —
    -- at most one, never both; neither = forever. At apply-time the applied
    -- snapshot's absolute end_date is resolved from this (a `cycle` span uses
    -- the membership's plan billing period). A 1-cycle span is the single-
    -- invoice discount that replaced the old `once` mode.
    duration_amount INTEGER CHECK (duration_amount > 0),
    duration_unit discount_duration_unit,
    end_date DATE,

    -- The current version of a discount. Editing inserts a new active version
    -- and flips the prior one to false (paper trail).
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (value_id),
    UNIQUE (value_id, gym_id),

    -- Exactly one of percentage_off / dollar_off is set.
    CHECK (num_nonnulls(percentage_off, dollar_off) = 1),

    -- duration_amount and duration_unit travel together.
    CONSTRAINT chk_discount_value_duration_pair CHECK (
        (duration_amount IS NULL) = (duration_unit IS NULL)
    ),

    -- Lifetime is at most one of: a duration span OR an explicit end_date.
    CONSTRAINT chk_discount_value_lifetime_exclusive CHECK (
        NOT (duration_amount IS NOT NULL AND end_date IS NOT NULL)
    ),

    -- A value version belongs to a discount identity in the same gym.
    CONSTRAINT fk_discount_value_discount_gym
        FOREIGN KEY (discount_id, gym_id)
        REFERENCES gym_discounts_unfiltered (discount_id, gym_id)
);

-- At most one active version per discount (0 is allowed mid-transition, 2+
-- rejected) — mirrors idx_max_one_active_price_per_plan.
CREATE UNIQUE INDEX idx_max_one_active_discount_value_per_discount
    ON gym_discount_values_unfiltered (discount_id) WHERE is_active = TRUE;

CREATE INDEX idx_gym_discount_values_discount
    ON gym_discount_values_unfiltered (discount_id);

-- A `custom` discount is ONE-SHOT: minted by a membership flow for exactly one
-- membership, so it has exactly ONE value version, forever. Re-versioning a
-- custom (a value edit) is rejected at the DB. Together with the
-- single-application trigger on member_membership_applied_discounts this makes
-- the custom lifecycle explicit (mint -> apply once -> archive), so cleaning up
-- a failed membership's minted customs can never touch another holder. Presets
-- version freely.
CREATE FUNCTION prevent_custom_discount_second_value()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM gym_discounts_unfiltered d
        WHERE d.discount_id = NEW.discount_id
          AND d.discount_type = 'custom'
    ) AND EXISTS (
        SELECT 1 FROM gym_discount_values_unfiltered v
        WHERE v.discount_id = NEW.discount_id
    ) THEN
        RAISE EXCEPTION
            'custom discount % is one-shot: it already has its single value version',
            NEW.discount_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_custom_discount_single_value
    BEFORE INSERT ON gym_discount_values_unfiltered
    FOR EACH ROW
    EXECUTE FUNCTION prevent_custom_discount_second_value();

-- View: passthrough of the base table (plain gym config, no Stripe gate).
CREATE VIEW gym_discount_values
WITH (security_invoker = true)
AS
SELECT * FROM gym_discount_values_unfiltered;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW gym_discount_values SET (security_invoker = true);
