-- Stripe-sync status: the sync's confirmation of whether a row's intended state
-- has landed on Stripe. This is the Stripe-convergence axis, kept ORTHOGONAL to
-- the lifecycle member_memberships_status view (active/cancelled/ended/frozen).
-- Shared by member_memberships and member_membership_applied_discounts; declared
-- here because member_memberships is the earliest-loaded table that uses it.
-- `applied`/`deleted` are stamped by the sync (the writeback) once Stripe
-- confirms; `preview_add`/`preview_remove` are reserved for preview-staging.
CREATE TYPE stripe_sync_status AS ENUM (
    'not_added',
    'applied',
    'deleted',
    'preview_add',
    'preview_remove'
);

-- Memberships are append-only: once created, a membership can only be
-- cancelled (cancel_date set), never modified back to active. To start
-- a new membership the client must INSERT a new row with a different
-- primary key (member_id, gym_id, plan_id).
CREATE TABLE member_memberships_unfiltered (
    item_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_membership_gym REFERENCES gyms(gym_id),
    plan_id UUID NOT NULL,
    price_id UUID NOT NULL CONSTRAINT fk_membership_price REFERENCES membership_plan_prices_unfiltered(price_id),
    -- Who PAYS for this membership: the member whose own Stripe customer +
    -- subscription bills this row. Always populated — for a normal family
    -- membership it is the resolved paying parent; for a self-paying linked
    -- member it is that member. The payment sync groups memberships by this
    -- column (one subscription per payer); account_linked_to_id on members is
    -- the authorization layer only (who is ALLOWED to pay for whom), never the
    -- billing key. Immutable once set — changing the payer is cancel-old +
    -- insert-new (the append-only model), never an in-place edit.
    paid_by_member_id UUID NOT NULL CONSTRAINT fk_membership_payer REFERENCES members(member_id),
    start_date DATE NOT NULL,
    end_date DATE,
    cancel_date DATE,
    last_paid_date DATE,
    next_due_date DATE,
    stripe_item_id VARCHAR,
    -- ONE-TIME memberships only: the consolidated invoice (in_…) this membership
    -- was billed on. stripe_item_id holds the per-membership invoice LINE id
    -- (distinct per membership sharing one invoice); this holds the shared invoice
    -- id so the membership still points back to its invoice. NULL for recurring
    -- (no single invoice). Service-role writeback, immutable once set.
    stripe_one_time_invoice_id VARCHAR,
    prorate BOOLEAN NOT NULL DEFAULT true,

    -- This membership's OWN post-discount price (minor units): the plan price
    -- minus THIS member's own discounts. Service_role writeback: computed at
    -- sync by PaymentSyncDiscounts (ongoing discounts always; once discounts
    -- only once the membership is on Stripe) and written per item_id. It is the
    -- per-membership share, NOT a plan/family-level total — the CRM derives a
    -- plan total by summing the rows.
    total_price INTEGER NOT NULL CHECK (total_price >= 0),

    -- Stripe-sync confirmation (service_role writeback). 'not_added' (default)
    -- = pending: the row is asking the sync to add it to Stripe; the sync stamps
    -- `applied` once Stripe confirms (and `deleted` when it removes the row).
    -- Orthogonal to the lifecycle status derived by the member_memberships_status
    -- view.
    stripe_sync_status stripe_sync_status NOT NULL DEFAULT 'not_added',

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

-- Index on member_id. The only other indexes are the PK/UNIQUE on item_id, which
-- cannot serve a `member_id`-keyed lookup, so every membership read and the three
-- INSERT triggers below (no-active / no-overlap / chronological-start) filter
-- `member_id = ...` with a sequential scan that grows with the table. The payment
-- sync reads each family's memberships (`member_id = ANY(...)`) on every billing
-- op, so without this the per-op cost grows linearly with total membership rows.
CREATE INDEX idx_member_memberships_member
    ON member_memberships_unfiltered (member_id);

-- Index on the payer. The payment sync partitions every family's active
-- memberships by paid_by_member_id (one subscription per payer) and the
-- reconciler lists distinct payers with live rows — both filter on this
-- column. Partial on the live rows (cancel_date IS NULL) to stay lean.
CREATE INDEX idx_member_memberships_paid_by
    ON member_memberships_unfiltered (paid_by_member_id)
    WHERE cancel_date IS NULL;

-- Discounts no longer live on the membership row: applying a discount writes a
-- frozen snapshot into member_membership_applied_discounts (keyed by item_id).
-- The old discount_ids JSONB column + its gym-match validation trigger are gone.

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

-- Trigger: price_id is immutable (NOT NULL at insert, never changes) — even at
-- service-role. A reprice is a NEW membership row at the new price (cancel the
-- old row + insert its successor, executed by the membership_reprice task);
-- nothing may repoint an existing row's price.
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

-- Trigger: paid_by_member_id is immutable once set — unconditional, no
-- 'migrating' exception. Changing who pays moves the line to a DIFFERENT
-- payer's Stripe subscription, so it is always cancel-old + insert-new (the
-- append-only model), never an in-place reassignment of the existing row.
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

-- Trigger: cancel_date locks only once the membership is actually REMOVED from
-- Stripe (stripe_sync_status = 'deleted'). Before that the cancel is unconfirmed,
-- so a DB-first cancel whose sync did not land can revert simply by clearing
-- cancel_date — no transient status to stage/un-stage.
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

-- Trigger: stripe_item_id is immutable once set — no exceptions, even at
-- service-role. The line id is the row's Stripe identity: NULL until the first
-- sync stamps it, frozen from then on. Any move to a different line (a reprice,
-- a payer change) is a NEW membership row (cancel old + insert new), never a
-- re-stamp of the existing row.
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

-- Trigger: stripe_one_time_invoice_id is immutable once set. Stamped once when a
-- one-time membership's consolidated invoice is created — a one-time invoice is
-- a terminal charge, not a line that moves between Stripe items.
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

-- Trigger: inserting a recurring membership requires all existing memberships
-- for the same user+gym to be ended or cancelled. Preview-staged rows
-- ('preview_add') are transient hypotheticals deleted in the preview's cleanup
-- and never billed — they skip the gate AND never block a real insert.
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

-- Trigger: no overlapping date ranges for recurring memberships on the same
-- plan. Preview-staged rows ('preview_add') skip the gate and never block a
-- real row (transient hypotheticals, deleted in the preview's cleanup).
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

-- Trigger: new recurring memberships must have a start_date on or after all
-- previous entries for the same (member_id, gym_id, plan_id). A SAME-day
-- successor is allowed (equality passes): a reprice cancels the old row
-- effective today and inserts its replacement starting today — two truly live
-- same-day rows remain impossible via the no-active + overlap triggers.
-- Preview-staged rows ('preview_add') skip the gate and never block a real row.
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

-- View: gate on BOTH the Stripe id and the sync-status enum. A row with no
-- `stripe_item_id` was never put on Stripe (not valid to surface), and the
-- sync-status hides `not_added` (pending) and `preview_*` (dry-run staging), so
-- the client only sees real synced rows (applied / deleted). The two
-- conditions are kept in lockstep with the `hide_incomplete_stripe_records` RLS
-- policy (`access_rules/member_memberships.sql`) so the view and RLS can't drift.
-- `member_memberships_status` reads this view, so cancelled (`deleted`) rows —
-- which keep their `stripe_item_id` — must stay visible.
CREATE VIEW member_memberships
WITH (security_invoker = true)
AS
SELECT * FROM member_memberships_unfiltered
WHERE stripe_item_id IS NOT NULL
  AND stripe_sync_status NOT IN ('not_added', 'preview_add', 'preview_remove');

ALTER VIEW member_memberships SET (security_invoker = true);

-- View: derives status from date fields (cancel_date > end_date > payer freeze window > active)
-- Freeze is per PAYER: the membership is frozen when its paid_by_member_id's
-- freeze window (on members) is active — the payer's pause_collection covers
-- exactly the memberships their subscription bills. A parent-paid membership
-- follows the parent's window (paid_by = parent); a self-paid membership
-- follows the self-payer's own window, independent of the linked parent.
CREATE VIEW member_memberships_status
WITH (security_invoker = true)
AS
SELECT mm.*,
    freeze_owner.freeze_start_date,
    freeze_owner.freeze_end_date,
    CASE
        WHEN mm.cancel_date IS NOT NULL AND mm.cancel_date <= (now() AT TIME ZONE g.timezone)::date THEN 'cancelled'
        WHEN mm.end_date IS NOT NULL AND mm.end_date <= (now() AT TIME ZONE g.timezone)::date THEN 'ended'
        WHEN freeze_owner.freeze_start_date IS NOT NULL
             AND freeze_owner.freeze_end_date IS NOT NULL
             AND freeze_owner.freeze_start_date <= (now() AT TIME ZONE g.timezone)::date
             AND (now() AT TIME ZONE g.timezone)::date <= freeze_owner.freeze_end_date THEN 'frozen'
        ELSE 'active'
    END AS status
FROM member_memberships mm
JOIN gyms g ON g.gym_id = mm.gym_id
JOIN members freeze_owner
    ON freeze_owner.member_id = mm.paid_by_member_id;

-- Safety net: CLI migration diffing can strip security_invoker from CREATE VIEW
ALTER VIEW member_memberships_status SET (security_invoker = true);
