-- The class's gym + points for a single-member check-in removal: verifies the
-- class exists (the gym auth boundary) and gives the points_worth to claw back.
-- Returns nothing for a deleted / absent class.
SELECT gym_id, points_worth
FROM gym_classes
WHERE class_id = CAST(:class_id AS UUID)
  AND is_deleted = FALSE
