SELECT DISTINCT member_id
FROM member_memberships
WHERE discount_ids @> :discount_id_json::jsonb
