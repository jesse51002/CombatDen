-- Invoices for the gym in the report window, with the payer's name and the
-- beneficiary names resolved from the paid_for JSONB array (the same
-- jsonb_array_elements_text pattern used by member_details/member_payments.sql).
-- Beneficiaries are joined into one "First Last; First Last" string for the
-- human report. Amounts are raw cents; the service converts to dollars.
SELECT
    i.invoice_time,
    i.invoice_id,
    i.status,
    i.total_amount,
    i.currency,
    i.paid_by_member_id,
    pm.first_name AS payer_first_name,
    pm.last_name AS payer_last_name,
    COALESCE((
        SELECT string_agg(
            bm.first_name || ' ' || bm.last_name, '; '
            ORDER BY bm.first_name, bm.last_name
        )
        FROM jsonb_array_elements_text(i.paid_for) AS pf(mid)
        JOIN members bm
            ON bm.member_id = CAST(pf.mid AS UUID)
           AND bm.gym_id = i.gym_id
    ), '') AS beneficiaries
FROM member_invoices i
LEFT JOIN members pm
    ON pm.member_id = i.paid_by_member_id
   AND pm.gym_id = i.gym_id
WHERE i.gym_id = CAST(:gym_id AS UUID)
  AND (
      CAST(:all_time AS BOOLEAN)
      OR (
          i.invoice_time >= CAST(:start_utc AS TIMESTAMPTZ)
          AND i.invoice_time < CAST(:end_utc AS TIMESTAMPTZ)
      )
  )
ORDER BY i.invoice_time ASC, i.invoice_id ASC
