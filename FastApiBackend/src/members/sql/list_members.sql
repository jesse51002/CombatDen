SELECT
    m.member_id,
    m.first_name,
    m.last_name,
    m.email,
    m.points_balance,
    m.status,
    m.last_class_days_ago,
    gr.rank_id AS rank_rank_id,
    gr.main_name AS rank_main_name,
    gr.sub_name AS rank_sub_name,
    gr.color AS rank_color,
    gr.image_url AS rank_image_url,
    gr.main_rank_num_order AS rank_main_rank_num_order,
    gr.sub_rank_num_order AS rank_sub_rank_num_order
FROM members_with_status m
LEFT JOIN gym_ranks gr ON gr.rank_id = m.current_rank_id
WHERE m.gym_id = :gym_id
  AND {status_filter}
  AND {search_filter}
ORDER BY m.last_name ASC, m.first_name ASC
LIMIT :limit OFFSET :offset
