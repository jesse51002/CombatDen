-- Log of reward redemptions. Separated from invoices/charges because
-- redemptions are point-based -- no money moves, so they don't belong in the
-- billing tables. point_cost is a snapshot at redemption time (the reward's
-- current point_cost may change later).
CREATE TABLE user_gym_reward_redemptions (
    redemption_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    gym_id UUID NOT NULL CONSTRAINT fk_redemption_gym REFERENCES gyms(gym_id),
    crm_user_id UUID NOT NULL,
    reward_id UUID NOT NULL CONSTRAINT fk_redemption_reward REFERENCES gym_rewards(reward_id),
    point_cost INTEGER NOT NULL CHECK (point_cost >= 0),
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (redemption_id),

    CONSTRAINT fk_redemption_user_gym
        FOREIGN KEY (crm_user_id, gym_id)
        REFERENCES user_gym_profiles_unfiltered (crm_user_id, gym_id),

    CONSTRAINT fk_redemption_reward_gym
        FOREIGN KEY (reward_id, gym_id)
        REFERENCES gym_rewards (reward_id, gym_id)
);

CREATE INDEX idx_reward_redemptions_user_gym_time
    ON user_gym_reward_redemptions (crm_user_id, gym_id, redeemed_at DESC);
