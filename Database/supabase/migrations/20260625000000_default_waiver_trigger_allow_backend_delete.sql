-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Relaxes prevent_default_waiver_removal() so the backend (service_role)
-- can hard-delete a gym's default waiver during gym-create teardown.
--
-- Before: DELETE and archive (is_deleted) of any is_default row were blocked
--         for ALL roles, including service_role.
-- After:  DELETE and archive are blocked for client roles only
--         (current_user IN ('authenticated','anon')). service_role may hard-
--         delete the default waiver row during GymsCreateService._cleanup_pending
--         (waiver was seeded before the Stripe account create; if that create
--         fails, cleanup must be able to remove the waiver row with no orphaned
--         Stripe account). is_default immutability stays enforced for ALL roles.
--
-- Only the function body changes; the trigger binding is unchanged.
-- Mirrors schemas/gym_waivers.sql (end state).

CREATE OR REPLACE FUNCTION prevent_default_waiver_removal()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- Block hard-delete for client roles only; service_role may delete
        -- during gym teardown (see GymsCreateService._cleanup_pending).
        IF OLD.is_default AND current_user IN ('authenticated', 'anon') THEN
            RAISE EXCEPTION
                'Cannot delete the default waiver for gym %', OLD.gym_id;
        END IF;
        RETURN OLD;
    END IF;
    -- UPDATE: block archiving a default waiver for client roles only.
    IF OLD.is_default AND NEW.is_deleted
        AND current_user IN ('authenticated', 'anon') THEN
        RAISE EXCEPTION
            'Cannot archive the default waiver for gym %', OLD.gym_id;
    END IF;
    -- is_default is immutable for ALL roles once set.
    IF OLD.is_default <> NEW.is_default THEN
        RAISE EXCEPTION
            'is_default is immutable on gym_waivers (waiver %)', OLD.waiver_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
