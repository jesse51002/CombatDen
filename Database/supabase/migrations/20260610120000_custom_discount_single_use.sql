-- A `custom` discount is one-shot and single-owner, enforced at the DB so
-- cleanup of a failed membership's minted customs can never touch another
-- holder: exactly ONE value version (never re-versioned) and exactly ONE
-- applied row (never applied to a second membership). Mirrors the triggers
-- declared in schemas/gym_discount_values.sql and
-- schemas/member_membership_applied_discounts.sql.

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

CREATE FUNCTION prevent_custom_discount_reapplication()
RETURNS TRIGGER AS $$
DECLARE
    v_discount_id UUID;
    v_discount_type VARCHAR;
BEGIN
    SELECT v.discount_id, d.discount_type
      INTO v_discount_id, v_discount_type
      FROM gym_discount_values_unfiltered v
      JOIN gym_discounts_unfiltered d ON d.discount_id = v.discount_id
     WHERE v.value_id = NEW.value_id;

    IF v_discount_type = 'custom' AND EXISTS (
        SELECT 1
          FROM member_membership_applied_discounts_unfiltered a
          JOIN gym_discount_values_unfiltered v2 ON v2.value_id = a.value_id
         WHERE v2.discount_id = v_discount_id
    ) THEN
        RAISE EXCEPTION
            'custom discount % is single-use and already applied to a membership',
            v_discount_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_custom_discount_single_application
    BEFORE INSERT ON member_membership_applied_discounts_unfiltered
    FOR EACH ROW
    EXECUTE FUNCTION prevent_custom_discount_reapplication();
