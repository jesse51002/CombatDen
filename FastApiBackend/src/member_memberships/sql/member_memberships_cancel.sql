UPDATE member_memberships mm
SET
    cancel_date = GREATEST(COALESCE(mm.next_due_date, CURRENT_DATE), CURRENT_DATE),
    stripe_item_id = NULL
WHERE mm.crm_user_id = :crm_user_id
  AND mm.gym_id      = :gym_id
  AND mm.plan_id     = :plan_id
