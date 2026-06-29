INSERT INTO gym_rewards (gym_id, title, image_url, price_label, point_cost, is_active)
VALUES (CAST(:gym_id AS UUID), :title, :image_url, :price_label, :point_cost, TRUE)
