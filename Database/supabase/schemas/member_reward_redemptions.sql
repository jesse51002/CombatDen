-- Log of point-based reward redemptions. point_cost is a snapshot at
-- redemption time (the reward's current point_cost may change later).
CREATE TABLE member_reward_redemptions (
    redemption_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_redemption_gym REFERENCES gyms(gym_id),
    member_id UUID NOT NULL,
    reward_id UUID NOT NULL CONSTRAINT fk_redemption_reward REFERENCES gym_rewards(reward_id),
    point_cost INTEGER NOT NULL CHECK (point_cost >= 0),
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (redemption_id),

    CONSTRAINT fk_redemption_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id),

    CONSTRAINT fk_redemption_reward_gym
        FOREIGN KEY (reward_id, gym_id)
        REFERENCES gym_rewards (reward_id, gym_id)
);

CREATE INDEX idx_member_reward_redemptions_member_gym_time
    ON member_reward_redemptions (member_id, gym_id, redeemed_at DESC);
