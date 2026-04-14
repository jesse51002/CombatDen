SELECT charge_id,
       invoice_id,
       crm_user_id,
       gym_id
FROM user_gym_charges
WHERE stripe_charge_id = :stripe_charge_id
  AND gym_id = :gym_id
  AND kind = 'payment'
LIMIT 1
