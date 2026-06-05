UPDATE gym_waivers
SET current_version_id = :version_id,
    updated_at = now()
WHERE waiver_id = :waiver_id
  AND gym_id = :gym_id
  AND is_deleted = false
RETURNING *
