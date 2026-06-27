-- Stripe-convergence axis (orthogonal to lifecycle status). Shared with member_membership_applied_discounts.
CREATE TYPE stripe_sync_status AS ENUM (
    'not_added',
    'applied',
    'deleted',
    'preview_add',
    'preview_remove'
);

-- Append-only: cancellation sets cancel_date; a new membership is a new row.
CREATE TABLE member_memberships_unfiltered (
    item_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_membership_gym REFERENCES gyms(gym_id),
    plan_id UUID NOT NULL,
    price_id UUID NOT NULL CONSTRAINT fk_membership_price REFERENCES membership_plan_prices_unfiltered(price_id),
    -- Payer's Stripe customer/subscription bills this row. Immutable; changing payer = cancel + new row.
    paid_by_member_id UUID NOT NULL CONSTRAINT fk_membership_payer REFERENCES members(member_id),
    start_date DATE NOT NULL,
    end_date DATE,
    cancel_date DATE,
    last_paid_date DATE,
    next_due_date DATE,
    stripe_item_id VARCHAR,
    -- One-time only: the consolidated invoice id. stripe_item_id holds the per-membership line id.
    stripe_one_time_invoice_id VARCHAR,

    -- Post-discount price for this membership (minor units). Service_role writeback by PaymentSyncDiscounts.
    total_price INTEGER NOT NULL CHECK (total_price >= 0),

    -- One-time/trial packs stack: quantity > 1 = N units on one invoice line.
    -- Recurring is always 1 (enforced by trg_recurring_quantity_must_be_one). Immutable after INSERT.
    quantity INTEGER NOT NULL DEFAULT 1
        CONSTRAINT member_membership_quantity_positive CHECK (quantity > 0),

    -- Service_role writeback. 'not_added' = pending sync; 'applied'/'deleted' after Stripe confirms.
    stripe_sync_status stripe_sync_status NOT NULL DEFAULT 'not_added',

    -- Idempotency token for one-time/trial start rows. Derived as uuid5(request_key, member:price).
    -- Retried requests reproduce the same key and collide on the partial unique index below.
    -- NULL for recurring (blocked by trg_recurring_no_active_memberships) and preview rows.
    idempotency_key UUID,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (item_id),
    UNIQUE (item_id, member_id),
    UNIQUE (item_id, gym_id),
    CONSTRAINT fk_membership_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    CONSTRAINT fk_membership_payer_gym
        FOREIGN KEY (paid_by_member_id, gym_id)
        REFERENCES members (member_id, gym_id),
    CONSTRAINT fk_membership_plan_gym
        FOREIGN KEY (plan_id, gym_id)
        REFERENCES membership_plans_unfiltered (plan_id, gym_id),
    CONSTRAINT fk_membership_price_plan
        FOREIGN KEY (price_id, plan_id)
        REFERENCES membership_plan_prices_unfiltered (price_id, plan_id)
);

CREATE INDEX idx_member_memberships_member
    ON member_memberships_unfiltered (member_id);

-- Partial on live rows only; payment sync and reconciler filter on this column.
CREATE INDEX idx_member_memberships_paid_by
    ON member_memberships_unfiltered (paid_by_member_id)
    WHERE cancel_date IS NULL;

-- Backs one-time start idempotency: retried rows collide here and are dropped by ON CONFLICT DO NOTHING.
CREATE UNIQUE INDEX idx_member_memberships_idempotency_key
    ON member_memberships_unfiltered (idempotency_key)
    WHERE idempotency_key IS NOT NULL;

-- Trigger: plan_id is immutable once set
CREATE OR REPLACE FUNCTION prevent_plan_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.plan_id IS DISTINCT FROM OLD.plan_id THEN
        RAISE EXCEPTION 'plan_id cannot be changed after creation'
            USING CONSTRAINT = 'plan_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_plan_id_overwrite
    BEFORE UPDATE OF plan_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_plan_id_overwrite();

-- Trigger: price_id is immutable — a reprice is cancel-old + new row.
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

-- Trigger: paid_by_member_id is immutable — changing payer is cancel-old + new row.
CREATE OR REPLACE FUNCTION prevent_paid_by_member_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.paid_by_member_id IS DISTINCT FROM OLD.paid_by_member_id THEN
        RAISE EXCEPTION 'paid_by_member_id cannot be changed after creation'
            USING CONSTRAINT = 'paid_by_member_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_price_id_overwrite
    BEFORE UPDATE OF price_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_price_id_overwrite();

CREATE TRIGGER trg_prevent_paid_by_member_id_overwrite
    BEFORE UPDATE OF paid_by_member_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_paid_by_member_id_overwrite();

-- Trigger: cancel_date locks once stripe_sync_status = 'deleted'. Before that, an unconfirmed cancel can revert.
CREATE OR REPLACE FUNCTION prevent_cancel_date_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.cancel_date IS NOT NULL
       AND NEW.cancel_date IS DISTINCT FROM OLD.cancel_date
       AND OLD.stripe_sync_status = 'deleted' THEN
        RAISE EXCEPTION 'cancel_date cannot be changed once the membership is removed from Stripe'
            USING CONSTRAINT = 'cancel_date_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_cancel_date_overwrite
    BEFORE UPDATE OF cancel_date ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_cancel_date_overwrite();

-- Trigger: stripe_item_id is immutable once set. Moving to a new line = cancel-old + new row.
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

CREATE TRIGGER trg_prevent_stripe_item_id_overwrite
    BEFORE UPDATE OF stripe_item_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_stripe_item_id_overwrite();

-- Trigger: stripe_one_time_invoice_id is immutable once set.
CREATE OR REPLACE FUNCTION prevent_stripe_one_time_invoice_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.stripe_one_time_invoice_id IS NOT NULL
       AND NEW.stripe_one_time_invoice_id IS DISTINCT FROM OLD.stripe_one_time_invoice_id THEN
        RAISE EXCEPTION 'stripe_one_time_invoice_id cannot be changed once set'
            USING CONSTRAINT = 'stripe_one_time_invoice_id_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_stripe_one_time_invoice_id_overwrite
    BEFORE UPDATE OF stripe_one_time_invoice_id ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_stripe_one_time_invoice_id_overwrite();

-- Trigger: idempotency_key is immutable once set (INSERT-time dedup token; NULL rows unaffected).
CREATE OR REPLACE FUNCTION prevent_idempotency_key_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.idempotency_key IS NOT NULL
       AND NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key THEN
        RAISE EXCEPTION 'idempotency_key cannot be changed once set'
            USING CONSTRAINT = 'idempotency_key_immutable';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_idempotency_key_overwrite
    BEFORE UPDATE OF idempotency_key ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_idempotency_key_overwrite();

-- Trigger: recurring plans cannot have an end_date
CREATE OR REPLACE FUNCTION check_recurring_no_end_date()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.end_date IS NOT NULL THEN
        SELECT plan_type INTO v_plan_type
        FROM membership_plans_unfiltered
        WHERE plan_id = NEW.plan_id;

        IF v_plan_type = 'recurring' THEN
            RAISE EXCEPTION 'recurring memberships cannot have an end_date'
                USING CONSTRAINT = 'recurring_no_end_date';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recurring_no_end_date
    BEFORE INSERT OR UPDATE OF end_date ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_no_end_date();

-- Trigger: recurring memberships must have quantity = 1 (one subscription item per plan).
CREATE OR REPLACE FUNCTION check_recurring_quantity_is_one()
RETURNS TRIGGER AS $$
DECLARE
    v_plan_type VARCHAR;
BEGIN
    IF NEW.quantity <> 1 THEN
        SELECT plan_type INTO v_plan_type
        FROM membership_plans_unfiltered
        WHERE plan_id = NEW.plan_id;

        IF v_plan_type = 'recurring' THEN
            RAISE EXCEPTION 'recurring memberships must have quantity = 1'
                USING CONSTRAINT = 'recurring_quantity_must_be_one';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_recurring_quantity_must_be_one
    BEFORE INSERT OR UPDATE OF quantity ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_quantity_is_one();

-- Trigger: no active recurring membership on the same plan may exist. preview_add rows skip the gate.
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

CREATE TRIGGER trg_recurring_no_active_memberships
    BEFORE INSERT ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_no_active_memberships();

-- Trigger: no overlapping date ranges for recurring memberships on the same plan. preview_add rows skip.
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

CREATE TRIGGER trg_recurring_no_overlapping_daterange
    BEFORE INSERT OR UPDATE OF cancel_date ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_no_overlapping_daterange();

-- Trigger: start_date must be >= all prior start_dates for the same plan. Same-day allowed (reprice). preview_add skips.
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

CREATE TRIGGER trg_recurring_chronological_start_date
    BEFORE INSERT ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION check_recurring_chronological_start_date();

-- Hides not-yet-synced (stripe_item_id IS NULL) and preview/pending rows.
-- Mirrors the hide_incomplete_stripe_records RLS policy in access_rules/.
CREATE VIEW member_memberships
WITH (security_invoker = true)
AS
SELECT * FROM member_memberships_unfiltered
WHERE stripe_item_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

ALTER VIEW member_memberships SET (security_invoker = true);

-- Derives lifecycle status from date fields. Freeze is per subject member (member_id), not payer.
CREATE VIEW member_memberships_status
WITH (security_invoker = true)
AS
SELECT mm.*,
    subject_member.freeze_start_date,
    subject_member.freeze_end_date,
    CASE
        WHEN mm.cancel_date IS NOT NULL AND mm.cancel_date <= (now() AT TIME ZONE g.timezone)::date THEN 'cancelled'
        WHEN mm.end_date IS NOT NULL AND mm.end_date <= (now() AT TIME ZONE g.timezone)::date THEN 'ended'
        WHEN subject_member.freeze_start_date IS NOT NULL
             AND subject_member.freeze_end_date IS NOT NULL
             AND subject_member.freeze_start_date <= (now() AT TIME ZONE g.timezone)::date
             AND (now() AT TIME ZONE g.timezone)::date <= subject_member.freeze_end_date THEN 'frozen'
        ELSE 'active'
    END AS status
FROM member_memberships mm
JOIN gyms g ON g.gym_id = mm.gym_id
JOIN members subject_member
    ON subject_member.member_id = mm.member_id;

-- Safety net: migration diffing can strip security_invoker from CREATE VIEW.
ALTER VIEW member_memberships_status SET (security_invoker = true);
