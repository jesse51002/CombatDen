-- Resolve a plan's requested waiver_ids against the gym's waiver catalog:
-- one row per id that EXISTS in the gym, with its type + archive state. The
-- service errors on any id that is missing (no row returned), archived, or
-- not a 'custom' waiver — special-purpose waivers (e.g. the payer-auth
-- agreement) are never plan-attachable. waiver_ids is JSONB with no FK, so
-- this is the write-time integrity check.
SELECT
    w.waiver_id,
    w.name,
    w.waiver_type,
    w.is_deleted
FROM jsonb_array_elements_text(CAST(:waiver_ids AS JSONB)) AS req(waiver_id)
JOIN gym_waivers w
    ON w.waiver_id = CAST(req.waiver_id AS UUID)
   AND w.gym_id = :gym_id
