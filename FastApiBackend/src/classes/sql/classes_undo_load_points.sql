-- The class's points_worth — the amount each attendee earned per check-in, so
-- un-occurring the class can claw it back.
SELECT points_worth
FROM gym_classes
WHERE class_id = CAST(:class_id AS UUID)
