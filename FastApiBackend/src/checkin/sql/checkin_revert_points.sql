-- Claw back a removed check-in's awarded points. UNLIKE the whole-occurrence
-- undo (which never touches points), a single-member removal reverses the
-- award. GREATEST(..., 0) respects the members.points_balance CHECK(>= 0) when
-- the member has since spent below the awarded amount (the balance floors at 0
-- rather than aborting).
UPDATE members
SET points_balance = GREATEST(points_balance - :points, 0)
WHERE member_id = CAST(:m AS UUID)
  AND gym_id = CAST(:g AS UUID)
