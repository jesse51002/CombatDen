UPDATE member_memberships mm
SET
    cancel_date = GREATEST(COALESCE(mm.next_due_date, CURRENT_DATE), CURRENT_DATE)
WHERE mm.item_id     = :item_id
  AND mm.crm_user_id = :crm_user_id
