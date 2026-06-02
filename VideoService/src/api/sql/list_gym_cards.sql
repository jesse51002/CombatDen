-- Slim gym-browser cards for every gym, sorted by id. The query/discipline
-- substring filter and pagination are applied in Python (only 76 gyms), exactly
-- matching the prior YAML behaviour.
SELECT
    g.gym_id,
    g.gym_type,
    g.theme,
    g.has_classes,
    g.has_rewards,
    (
        SELECT count(*)
        FROM video_gym_feed f
        WHERE f.gym_id = g.gym_id AND f.status = 'good'
    ) AS video_count
FROM video_gym g
ORDER BY g.gym_id
