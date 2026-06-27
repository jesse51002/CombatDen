-- Hand-authored migration.
-- Adds an immutability trigger on member_memberships_unfiltered.idempotency_key
-- to match the existing prevent_stripe_item_id_overwrite / prevent_stripe_one_time_invoice_id_overwrite pattern.
-- idempotency_key is a backend-only INSERT-time dedup token; NULL rows (recurring/preview) are unaffected.

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

DROP TRIGGER IF EXISTS trg_prevent_idempotency_key_overwrite ON member_memberships_unfiltered;

CREATE TRIGGER trg_prevent_idempotency_key_overwrite
    BEFORE UPDATE OF idempotency_key ON member_memberships_unfiltered
    FOR EACH ROW EXECUTE FUNCTION prevent_idempotency_key_overwrite();
