UPDATE members
SET linked_discount_id = :linked_discount_id
WHERE member_id = :member_id
  AND gym_id = :gym_id
