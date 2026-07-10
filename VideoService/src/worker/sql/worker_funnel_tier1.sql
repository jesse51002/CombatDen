-- Tier 1 scan candidates: pool videos this gym's OWN search queries surfaced
-- (source_queries overlaps the current spec queries), discipline-filtered. A
-- video whose disciplines overlap the gym's is in; a freshly-scraped UNTAGGED
-- video (disciplines still []) is ALSO in — it has not been enriched yet, so it
-- cannot be discipline-matched, and it must reach enrich+scan on the run that
-- scraped it (the scan then judges fit). jsonb_exists_any(col, arr) is the
-- functional form of the `?|` array-overlap operator (avoids the `?` bind clash
-- with SQLAlchemy/asyncpg entirely).
--
-- The whole selection is bounded IN-DB: the incremental exclusion (the previous
-- completed run's already-verdicted ids, carried forward instead of rescanned) is
-- pushed down as :exclude_ids, and the per-run budget as ORDER BY relevance +
-- LIMIT :budget — so the most-relevant :budget candidates come back and a huge
-- query-overlap pool is never loaded into Python to be sliced. :exclude_ids is
-- bound as a plain TEXT[] (asyncpg infers the element type from the video_id
-- comparison; an empty list matches nothing → excludes nothing), mirroring the
-- tier-2 probe's exclusion.
SELECT video_id, relevance_index
FROM video
WHERE jsonb_exists_any(source_queries, CAST(:queries AS TEXT[]))
  AND (
      jsonb_exists_any(disciplines, CAST(:disciplines AS TEXT[]))
      OR jsonb_array_length(disciplines) = 0
  )
  AND NOT (video_id = ANY(:exclude_ids))
ORDER BY relevance_index ASC, video_id ASC
LIMIT :budget;
