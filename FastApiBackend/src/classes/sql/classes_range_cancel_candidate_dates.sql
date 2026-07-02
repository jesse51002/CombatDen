-- Distinct original_dates in [start_date, end_date] carrying a live
-- reservation (class_signups) OR attendance (member_attendance) row for
-- this class -- the only dates a range cancel could possibly need to tear
-- down (a date with neither has nothing to reverse). class_id alone
-- disambiguates the gym (FK'd to one gym_classes row), so no gym_id filter
-- is needed.
SELECT original_date
FROM class_signups
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date >= CAST(:start_date AS DATE)
  AND original_date <= CAST(:end_date AS DATE)
UNION
SELECT original_date
FROM member_attendance
WHERE class_id = CAST(:class_id AS UUID)
  AND original_date >= CAST(:start_date AS DATE)
  AND original_date <= CAST(:end_date AS DATE)
