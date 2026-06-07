SELECT charge_id,
       invoice_id,
       member_id,
       gym_id
FROM member_charges
WHERE stripe_charge_id = :stripe_charge_id
  AND gym_id = :gym_id
  AND kind = 'payment'
LIMIT 1
