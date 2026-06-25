-- Gym discount IDENTITY (preset | custom) — coupon-free.
--
-- A discount's actual VALUES (percent/dollar, lifetime spec) live in versioned,
-- immutable rows on gym_discount_values. Editing a discount's value mints a new
-- active version there (paper trail); the identity (name, type) stays stable.
-- Applied snapshots reference a value version, so a member's discount is frozen
-- to the exact version it was applied at.
--
-- The discount_mode / discount_duration_unit enums are declared in
-- gym_discount_values.sql (the earliest-loaded consumer of them).
CREATE TABLE gym_discounts_unfiltered (
    discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_discount_gym REFERENCES gyms(gym_id),
    discount_name VARCHAR NOT NULL CHECK (discount_name <> ''),
    discount_type VARCHAR NOT NULL CHECK (discount_type IN ('preset', 'custom')),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (discount_id),
    UNIQUE (discount_id, gym_id)
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
