INSERT INTO gym_video_query (gym_id, query)
VALUES (CAST(:gym_id AS UUID), :query)
