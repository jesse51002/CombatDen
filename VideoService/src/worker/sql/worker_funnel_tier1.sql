-- Tier 1 scan candidates: pool videos this gym's OWN search queries surfaced
-- (source_queries overlaps the current spec queries), discipline-filtered. A
-- video whose disciplines overlap the gym's is in; a freshly-scraped UNTAGGED
-- video (disciplines still []) is ALSO in — it has not been enriched yet, so it
-- cannot be discipline-matched, and it must reach enrich+scan on the run that
-- scraped it (the scan then judges fit). jsonb_exists_any(col, arr) is the
-- functional form of the `?|` array-overlap operator (avoids the `?` bind clash
-- with SQLAlchemy/asyncpg entirely). Ordered by relevance so a budget truncation
-- keeps the most relevant.
SELECT video_id, relevance_index
FROM video
WHERE jsonb_exists_any(source_queries, CAST(:queries AS TEXT[]))
  AND (
      jsonb_exists_any(disciplines, CAST(:disciplines AS TEXT[]))
      OR jsonb_array_length(disciplines) = 0
  )
ORDER BY relevance_index ASC, video_id ASC;
