-- Members whose record was created in the report window (members.created_at is
-- a timestamptz, so the window is the UTC half-open range). Covers every member
-- -- engagement-only and billing -- since the general members table has no
-- billing-complete filter.
SELECT
    mem.created_at,
    mem.member_id,
    mem.first_name,
    mem.last_name,
    mem.email
FROM members mem
WHERE mem.gym_id = CAST(:gym_id AS UUID)
  AND (
      CAST(:all_time AS BOOLEAN)
      OR (
          mem.created_at >= CAST(:start_utc AS TIMESTAMPTZ)
          AND mem.created_at < CAST(:end_utc AS TIMESTAMPTZ)
      )
  )
ORDER BY mem.created_at ASC, mem.member_id ASC
