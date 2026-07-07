-- Member counts per sub-position for one MAIN rank — the rank-detail
-- page's per-sub breakdown. SPARSE: one row per sub-index that has at
-- least one member (empty sub-slots are absent; the CRM fills 0 for them
-- using the rank's sub_rank_count). On a 'none' gym members carry a NULL
-- sub-index, so this returns a single {null, total} row. The service sums
-- the counts for the total-on-rank figure.
SELECT
    m.current_sub_index AS sub_index,
    COUNT(*) AS count
FROM members m
WHERE m.gym_id = CAST(:gym_id AS UUID)
  AND m.current_rank_id = CAST(:rank_id AS UUID)
GROUP BY m.current_sub_index
ORDER BY m.current_sub_index ASC NULLS FIRST
