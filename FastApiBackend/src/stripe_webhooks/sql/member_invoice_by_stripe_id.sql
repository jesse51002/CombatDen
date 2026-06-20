SELECT invoice_id,
       paid_by_member_id
FROM member_invoices
WHERE stripe_invoice_id = :stripe_invoice_id
  AND gym_id = :gym_id
LIMIT 1
