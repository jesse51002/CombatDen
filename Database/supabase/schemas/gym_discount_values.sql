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
-- The discount_mode / discount_duration_unit enums are declared here (the
-- earliest-loaded consumer): gym_discounts is now identity-only and the applied
-- snapshots reach mode via value_id -> gym_discount_values.
CREATE TYPE discount_mode AS ENUM ('once', 'ongoing');

-- Duration span unit for an ongoing discount's lifetime. Dedicated to discounts
-- (day/week/month) — distinct from membership_plans' duration_unit
-- (week/month/year), which is a different domain.
CREATE TYPE discount_duration_unit AS ENUM ('day', 'week', 'month');

CREATE TABLE gym_discount_values_unfiltered (
    value_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    discount_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_discount_value_gym REFERENCES gyms(gym_id),

    percentage_off FLOAT CHECK (percentage_off > 0 AND percentage_off <= 100),
    dollar_off INTEGER CHECK (dollar_off > 0),

    -- Lifetime spec: discount_mode (once | ongoing) PLUS, for ongoing, an end
    -- set by EITHER a duration span (duration_amount + duration_unit) OR an
    -- explicit end_date — exactly one, never both; neither = forever. At
    -- apply-time the applied snapshot's absolute end_date is resolved from this.
    discount_mode discount_mode NOT NULL,
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

-- View: passthrough of the base table (plain gym config, no Stripe gate).
CREATE VIEW gym_discount_values
WITH (security_invoker = true)
AS
SELECT * FROM gym_discount_values_unfiltered;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW gym_discount_values SET (security_invoker = true);
