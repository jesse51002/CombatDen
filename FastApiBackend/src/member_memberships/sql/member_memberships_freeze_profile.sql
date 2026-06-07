UPDATE members
SET freeze_start_date = :freeze_start_date,
    freeze_end_date   = :freeze_end_date
WHERE member_id = :member_id
  AND gym_id    = :gym_id
