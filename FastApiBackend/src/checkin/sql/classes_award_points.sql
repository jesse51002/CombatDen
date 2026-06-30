-- Award a class's points to the member's running balance. Run only on a NEW
-- attendance row (never on an ON CONFLICT idempotent repeat) and in the same
-- transaction as the attendance INSERT. The members.points_balance CHECK(>= 0)
-- guards against a negative balance; awards only ever add.
UPDATE members
SET points_balance = points_balance + :points
WHERE member_id = CAST(:m AS UUID)
  AND gym_id = CAST(:g AS UUID)
