-- A gym's points-store reward cards (RewardCard). Surrogate UUID PK; the API
-- serves them ORDER BY points_cost (natural for a points store). Absent when the
-- gym has no rewards authored (template_gym.has_rewards = FALSE, zero rows).

CREATE TABLE template_gym_reward (
    reward_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id TEXT NOT NULL
        CONSTRAINT fk_template_gym_reward_gym REFERENCES template_gym(gym_id) ON DELETE CASCADE,
    title TEXT NOT NULL CONSTRAINT template_gym_reward_title_nonempty CHECK (title <> ''),
    image_url TEXT NOT NULL CONSTRAINT template_gym_reward_image_url_nonempty CHECK (image_url <> ''),
    price_label TEXT NOT NULL CONSTRAINT template_gym_reward_price_label_nonempty CHECK (price_label <> ''),
    points_cost INTEGER NOT NULL CONSTRAINT template_gym_reward_points_cost_nonneg CHECK (points_cost >= 0),
    CONSTRAINT pk_template_gym_reward PRIMARY KEY (reward_id)
);

CREATE INDEX idx_template_gym_reward_gym ON template_gym_reward (gym_id);
