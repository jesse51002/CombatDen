UPDATE members
SET freeze_start_date = NULL,
    freeze_end_date   = NULL
WHERE member_id = :member_id
  AND gym_id    = :gym_id
