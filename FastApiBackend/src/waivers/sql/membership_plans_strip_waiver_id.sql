-- Remove an archived waiver's id from every plan's required-waiver list in
-- the gym. waiver_ids is JSONB with no FK, so the archive path strips the id
-- to keep plans truthful (the start gate already ignores archived waivers,
-- and the plan editor would otherwise silently re-save the dead id). Targets
-- the base table so pre-Stripe pending plan rows are stripped too.
UPDATE membership_plans_unfiltered
   SET waiver_ids = COALESCE(
        (
            SELECT jsonb_agg(t.elem)
            FROM jsonb_array_elements_text(waiver_ids) AS t(elem)
            WHERE t.elem <> :waiver_id
        ),
        CAST('[]' AS JSONB)
   )
 WHERE gym_id = :gym_id
   AND waiver_ids @> jsonb_build_array(CAST(:waiver_id AS TEXT))
