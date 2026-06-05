-- Insert a new ACTIVE discount value version for a discount. Editing a discount
-- inserts a new version here (after deactivating the prior active one) — the
-- value rows are an immutable paper trail. Applied snapshots reference value_id.
INSERT INTO gym_discount_values_unfiltered (
    discount_id,
    gym_id,
    percentage_off,
    dollar_off,
    discount_mode,
    duration_amount,
    duration_unit,
    end_date,
    is_active
) VALUES (
    :discount_id,
    :gym_id,
    :percentage_off,
    :dollar_off,
    :discount_mode,
    :duration_amount,
    :duration_unit,
    :end_date,
    true
)
RETURNING value_id, percentage_off, dollar_off, discount_mode,
          duration_amount, duration_unit, end_date
