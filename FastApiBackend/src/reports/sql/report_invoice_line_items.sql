-- Line items of the gym's invoices in the report window. Line items carry no
-- timestamp of their own, so the window is applied to the parent invoice's
-- invoice_time (also selected so each row shows when its invoice was cut).
-- Amounts are raw cents; the service converts to dollars.
SELECT
    inv.invoice_time,
    li.invoice_id,
    li.line_item_id,
    li.item_type,
    li.name,
    li.amount,
    li.quantity,
    li.item_id
FROM member_invoice_line_items li
JOIN member_invoices inv
    ON inv.invoice_id = li.invoice_id
WHERE li.gym_id = CAST(:gym_id AS UUID)
  AND (
      CAST(:all_time AS BOOLEAN)
      OR (
          inv.invoice_time >= CAST(:start_utc AS TIMESTAMPTZ)
          AND inv.invoice_time < CAST(:end_utc AS TIMESTAMPTZ)
      )
  )
ORDER BY inv.invoice_time ASC, li.invoice_id ASC, li.line_item_id ASC
