-- Bump members.last_class to a fresh check-in's EFFECTIVE start instant
-- (the resolved occurrence's occurred_at, passed as a bind param -- no
-- no join needed), only forward: a retroactive check-in of an
-- earlier occurrence than the member's current last_class never regresses it.
UPDATE members
SET last_class = :occurred_at
WHERE member_id = :member_id
  AND (last_class IS NULL OR :occurred_at > last_class)
