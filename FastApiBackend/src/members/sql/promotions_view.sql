SELECT
    p.crm_user_id,
    p.first_name,
    p.last_name,
    p.photo_url,
    p.current_rank,
    p.created_at AS profile_created_at,
    g.rank_1_name, g.rank_2_name, g.rank_3_name,
    g.rank_4_name, g.rank_5_name,
    g.estimated_classes_rank_1,
    g.estimated_classes_rank_2,
    g.estimated_classes_rank_3,
    g.estimated_classes_rank_4,
    g.estimated_classes_rank_5,
    COALESCE(cls.classes_in_rank, 0) AS classes_in_rank,
    (SELECT MAX(ua.time)
     FROM user_activities ua
     WHERE ua.crm_user_id = p.crm_user_id
       AND ua.gym_id = p.gym_id
       AND ua.activity_type = 'rank_change'
    ) AS last_rank_change
FROM user_gym_profiles p
JOIN member_memberships m
    ON p.crm_user_id = m.crm_user_id
    AND p.gym_id = m.gym_id
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON p.gym_id = g.gym_id
LEFT JOIN LATERAL (
    SELECT COUNT(*) AS classes_in_rank
    FROM user_activities ua
    WHERE ua.crm_user_id = p.crm_user_id
      AND ua.gym_id = p.gym_id
      AND ua.activity_type = 'class_attended'
      AND ua.time >= COALESCE(
          (SELECT MAX(ua2.time)
           FROM user_activities ua2
           WHERE ua2.crm_user_id = p.crm_user_id
             AND ua2.gym_id = p.gym_id
             AND ua2.activity_type = 'rank_change'),
          p.created_at
      )
) cls ON true
{where_clause}
ORDER BY
    CASE p.current_rank
        WHEN 1 THEN g.estimated_classes_rank_1
        WHEN 2 THEN g.estimated_classes_rank_2
        WHEN 3 THEN g.estimated_classes_rank_3
        WHEN 4 THEN g.estimated_classes_rank_4
        WHEN 5 THEN g.estimated_classes_rank_5
        ELSE 9999
    END - COALESCE(cls.classes_in_rank, 0) ASC
LIMIT :limit OFFSET :offset
