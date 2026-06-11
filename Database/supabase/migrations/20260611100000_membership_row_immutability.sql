-- Full membership-row immutability: price_id and stripe_item_id can never
-- change once they hold a value — a reprice is cancel-old-row + insert-new-row
-- (the membership_reprice task), never an in-place mutation. Drops the
-- 'migrating' exception from the stripe_item_id guard, adds the price_id
-- guard, lets the recurring INSERT triggers admit a same-day successor row and
-- ignore preview-staged ('preview_add') rows, and relaxes the custom-discount
-- single-application trigger to single-LIVE-application so the reprice can
-- copy a custom application onto the successor row. Mirrors
-- schemas/member_memberships.sql and
-- schemas/member_membership_applied_discounts.sql.

-- stripe_item_id: immutable once set, no exceptions (the 'migrating' carve-out
-- is gone — nothing re-stamps a line id anymore).
CREATE OR REPLACE FUNCTION prevent_stripe_item_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stripe_item_id IS NOT NULL
       AND NEW.stripe_item_id IS DISTINCT FROM OLD.stripe_item_id THEN
        RAISE EXCEPTION 'stripe_item_id cannot be changed once set'
            USING CONSTRAINT = 'stripe_item_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- price_id: immutable, even at service-role.
CREATE OR REPLACE FUNCTION prevent_price_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.price_id IS DISTINCT FROM OLD.price_id THEN
        RAISE EXCEPTION 'price_id cannot be changed after creation'
            USING CONSTRAINT = 'price_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_price_id_overwrite
    BEFORE UPDATE OF price_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_price_id_overwrite();

-- Recurring INSERT gates: skip + ignore preview-staged rows; cancelled-today
-- counts as inactive (unchanged), so a successor inserted the same day passes.
CREATE OR REPLACE FUNCTION check_recurring_no_active_memberships()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
    v_active_count INTEGER;
    v_today DATE;
BEGIN
    IF NEW.stripe_sync_status = 'preview_add' THEN
        RETURN NEW;
    END IF;

    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT (now() AT TIME ZONE g.timezone)::date INTO v_today
        FROM gyms g WHERE g.gym_id = NEW.gym_id;

        SELECT COUNT(*) INTO v_active_count
        FROM member_memberships_unfiltered mm
        WHERE mm.member_id = NEW.member_id
          AND mm.gym_id = NEW.gym_id
          AND mm.plan_id = NEW.plan_id
          AND mm.item_id <> NEW.item_id
          AND mm.stripe_sync_status <> 'preview_add'
          AND (mm.cancel_date IS NULL OR mm.cancel_date > v_today)
          AND (mm.end_date IS NULL OR mm.end_date > v_today);

        IF v_active_count > 0 THEN
            RAISE EXCEPTION 'cannot add recurring membership while an active membership on the same plan exists'
                USING CONSTRAINT = 'recurring_requires_no_active';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_recurring_no_overlapping_daterange()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.stripe_sync_status = 'preview_add' THEN
        RETURN NEW;
    END IF;

    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        IF EXISTS (
            SELECT 1
            FROM member_memberships_unfiltered mm
            WHERE mm.member_id = NEW.member_id
              AND mm.gym_id = NEW.gym_id
              AND mm.plan_id = NEW.plan_id
              AND mm.item_id <> NEW.item_id
              AND mm.stripe_sync_status <> 'preview_add'
              AND daterange(mm.start_date, mm.cancel_date, '[)')
               && daterange(NEW.start_date, NEW.cancel_date, '[)')
        ) THEN
            RAISE EXCEPTION 'recurring membership overlaps an existing membership on the same plan'
                USING CONSTRAINT = 'recurring_no_overlapping_daterange';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Chronological start: equality now passes (same-day successor); only a
-- back-dated insert is rejected.
CREATE OR REPLACE FUNCTION check_recurring_chronological_start_date()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
    v_max_start_date DATE;
BEGIN
    IF NEW.stripe_sync_status = 'preview_add' THEN
        RETURN NEW;
    END IF;

    SELECT plan_type INTO v_plan_type
    FROM membership_plans_unfiltered
    WHERE plan_id = NEW.plan_id;

    IF v_plan_type = 'recurring' THEN
        SELECT MAX(mm.start_date) INTO v_max_start_date
        FROM member_memberships_unfiltered mm
        WHERE mm.member_id = NEW.member_id
          AND mm.gym_id = NEW.gym_id
          AND mm.plan_id = NEW.plan_id
          AND mm.item_id <> NEW.item_id
          AND mm.stripe_sync_status <> 'preview_add';

        IF v_max_start_date IS NOT NULL AND NEW.start_date < v_max_start_date THEN
            RAISE EXCEPTION 'start_date must be on or after % (latest existing start_date for this plan)', v_max_start_date
                USING CONSTRAINT = 'recurring_chronological_start_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Custom discounts: single LIVE application instead of single application
-- ever — the reprice's carry-over copy (old membership already cancelled
-- effective today) passes; a second application to a live membership still
-- fails.
CREATE OR REPLACE FUNCTION prevent_custom_discount_reapplication()
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
