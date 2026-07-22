-- All money-movement charges (payments AND refunds, every status) for the gym
-- in the report window, joined to the payer's name. Backs payments.csv and the
-- summary money math. The window is a bound predicate: when the all-time flag
-- is true the whole window clause short-circuits to true, so no time filter
-- applies; otherwise charge_time is bounded to the UTC half-open window.
-- Amounts are raw cents here; the service converts to dollars at the CSV edge.
SELECT
    c.charge_time,
    c.charge_id,
    c.invoice_id,
    c.kind,
    c.status,
    c.amount,
    c.currency,
    c.payment_method_type,
    c.card_last_four,
    c.paid_by_member_id,
    m.first_name AS payer_first_name,
    m.last_name AS payer_last_name
FROM member_charges c
LEFT JOIN members m
    ON m.member_id = c.paid_by_member_id
   AND m.gym_id = c.gym_id
WHERE c.gym_id = CAST(:gym_id AS UUID)
  AND (
      CAST(:all_time AS BOOLEAN)
      OR (
          c.charge_time >= CAST(:start_utc AS TIMESTAMPTZ)
          AND c.charge_time < CAST(:end_utc AS TIMESTAMPTZ)
      )
  )
ORDER BY c.charge_time ASC, c.charge_id ASC
