CREATE TABLE gym_history (
    gym_id UUID NOT NULL CONSTRAINT fk_history_gym REFERENCES gyms(gym_id),
    date DATE NOT NULL,
    members_total INTEGER NOT NULL CHECK (members_total >= 0),
    members_churned INTEGER NOT NULL CHECK (members_churned >= 0),
    members_gained INTEGER NOT NULL CHECK (members_gained >= 0),
    members_retained INTEGER NOT NULL CHECK (members_retained >= 0),
    revenue FLOAT NOT NULL CHECK (revenue >= 0),
    PRIMARY KEY (gym_id, date)
);

-- Enable Row Level Security
ALTER TABLE gym_history ENABLE ROW LEVEL SECURITY;

-- Policy: Gym owners can read their gym's history (read-only, backend generates data)
CREATE POLICY "Gym owners can view own gym history"
    ON gym_history
    FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM gyms
            WHERE gyms.gym_id = gym_history.gym_id
            AND gyms.owner_id = auth.uid()
        )
    );
