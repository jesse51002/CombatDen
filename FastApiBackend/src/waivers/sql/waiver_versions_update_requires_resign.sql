-- Flip requires_resign on the CURRENT version in place — the
-- mistake-correction path for the save-time re-sign choice. Changing it
-- moves the re-sign FLOOR: true raises the floor to this version (prior
-- signers must re-sign); false lowers it back to the previous
-- requires_resign version (their signatures count again).
UPDATE gym_waiver_versions
   SET requires_resign = CAST(:requires_resign AS BOOLEAN)
 WHERE version_id = :version_id
   AND gym_id = :gym_id
RETURNING version_id
