CREATE TABLE members (
    member_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    user_id UUID CONSTRAINT fk_member_user REFERENCES auth.users(id),
    gym_id UUID NOT NULL CONSTRAINT fk_member_gym REFERENCES gyms(gym_id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_class TIMESTAMPTZ,
    first_name VARCHAR NOT NULL CHECK (first_name <> ''),
    last_name VARCHAR NOT NULL CHECK (last_name <> ''),
    email VARCHAR,
    points_balance INTEGER NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
    current_rank_id UUID,
    PRIMARY KEY (member_id),
    UNIQUE (member_id, gym_id),
    CONSTRAINT fk_member_current_rank
        FOREIGN KEY (current_rank_id, gym_id)
        REFERENCES gym_ranks (rank_id, gym_id)
);

-- Partial unique index: a user can only have one member record per gym
CREATE UNIQUE INDEX unique_member_user_gym
    ON members (user_id, gym_id)
    WHERE user_id IS NOT NULL;

-- Trigger: once user_id is set, it cannot be changed to a different value
CREATE OR REPLACE FUNCTION prevent_user_id_overwrite()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.user_id IS NOT NULL AND NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'user_id cannot be changed once set (member_id: %)', OLD.member_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_user_id_overwrite
    BEFORE UPDATE OF user_id ON members
    FOR EACH ROW EXECUTE FUNCTION prevent_user_id_overwrite();
