-- Hand-authored migration.
-- prevent_cancel_date_overwrite() gains a second lock branch: a written
-- cancel_date on a ONE_TIME / TRIAL membership (plan_type looked up from
-- membership_plans_unfiltered by OLD.plan_id) is now IMMUTABLE immediately --
-- their manual cancel is a pure DB write with no Stripe confirmation step to
-- wait for, so a pack's termination is final the moment it lands. RECURRING
-- keeps the existing lock-only-once-'deleted' behavior. The trigger
-- (trg_prevent_cancel_date_overwrite) is unchanged and needs no re-create --
-- CREATE OR REPLACE of the function is enough.

CREATE OR REPLACE FUNCTION prevent_cancel_date_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.cancel_date IS NOT NULL
       AND NEW.cancel_date IS DISTINCT FROM OLD.cancel_date THEN
        IF OLD.stripe_sync_status = 'deleted' THEN
            RAISE EXCEPTION 'cancel_date cannot be changed once the membership is removed from Stripe'
                USING CONSTRAINT = 'cancel_date_immutable';
        END IF;
        IF (
            SELECT plan_type FROM membership_plans_unfiltered
            WHERE plan_id = OLD.plan_id
        ) IN ('trial', 'one_time') THEN
            RAISE EXCEPTION 'cancel_date is final on a one-time / trial membership'
                USING CONSTRAINT = 'cancel_date_immutable';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
