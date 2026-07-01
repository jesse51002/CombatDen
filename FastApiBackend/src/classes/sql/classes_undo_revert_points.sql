-- Claw back one attendee's points when their occurrence is un-occurred.
-- GREATEST(..., 0) floors the balance at 0: points already spent on rewards are
-- never "un-bought" -- if they used them, it is what it is.
UPDATE members
SET points_balance = GREATEST(points_balance - :points, 0)
WHERE member_id = CAST(:m AS UUID)
  AND gym_id = CAST(:g AS UUID)
