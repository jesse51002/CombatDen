UPDATE member_memberships_unfiltered
SET discount_ids = COALESCE(
    (SELECT jsonb_agg(elem)
     FROM jsonb_array_elements(discount_ids) AS elem
     WHERE elem::text != :discount_id_text),
    '[]'::jsonb
)
WHERE discount_ids @> :discount_id_json::jsonb
RETURNING crm_user_id
