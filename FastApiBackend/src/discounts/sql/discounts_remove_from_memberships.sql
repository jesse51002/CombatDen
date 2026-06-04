UPDATE member_memberships_unfiltered
SET discount_ids = COALESCE(
    (SELECT jsonb_agg(elem)
     FROM jsonb_array_elements(discount_ids) AS elem
     WHERE CAST(elem AS text) != :discount_id_text),
    CAST('[]' AS jsonb)
)
WHERE discount_ids @> CAST(:discount_id_json AS jsonb)
RETURNING member_id
