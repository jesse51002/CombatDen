-- Gym discount IDENTITY (preset | custom | linked) — coupon-free.
--
-- A discount's actual VALUES (percent/dollar, lifetime spec) live in versioned,
-- immutable rows on gym_discount_values. Editing a discount's value mints a new
-- active version there (paper trail); the identity (name, type) stays stable.
-- Applied snapshots reference a value version, so a member's discount is frozen
-- to the exact version it was applied at.
--
-- A `linked` (family) discount is a real discount entry like any other — it has
-- a versioned value on gym_discount_values and a stable id. A membership plan
-- references linked discounts by id (membership_plans.linked_discount_ids,
-- one per family tier); applying one freezes a snapshot to its active value just
-- like any discount. The `linked` tag marks it as a family discount and keeps it
-- out of the regular per-membership discount picker.
--
-- The discount_duration_unit enum is declared in gym_discount_values.sql
-- (the earliest-loaded consumer of it).
CREATE TABLE gym_discounts_unfiltered (
    discount_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_discount_gym REFERENCES gyms(gym_id),
    discount_name VARCHAR NOT NULL CHECK (discount_name <> ''),
    discount_type VARCHAR NOT NULL CHECK (discount_type IN ('preset', 'custom', 'linked')),
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
