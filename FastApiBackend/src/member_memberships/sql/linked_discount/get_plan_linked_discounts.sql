SELECT discount_id, membership_plan_id, linked_discount_num, dollar_off
FROM gym_discounts
WHERE gym_id = :gym_id
  AND membership_plan_id = ANY(:plan_ids)
  AND discount_type = 'linked'
  AND is_deleted = false
ORDER BY membership_plan_id, linked_discount_num ASC
