UPDATE member_memberships_unfiltered mm
SET
    cancel_date = GREATEST(COALESCE(mm.next_due_date, :gym_today), :gym_today)
WHERE mm.item_id     = :item_id
  AND mm.crm_user_id = :crm_user_id
RETURNING cancel_date
