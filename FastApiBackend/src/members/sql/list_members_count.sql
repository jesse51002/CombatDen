SELECT COUNT(*) AS total
FROM members_with_status
WHERE gym_id = :gym_id
  AND {status_filter}
  AND {search_filter}
