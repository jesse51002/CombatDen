UPDATE member_memberships_unfiltered
SET last_paid_date = :last_paid_date,
    next_due_date = :next_due_date
WHERE item_id = :item_id
  AND gym_id = :gym_id
