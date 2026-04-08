SELECT DISTINCT crm_user_id
FROM member_memberships
WHERE discount_ids @> :discount_id_json::jsonb
