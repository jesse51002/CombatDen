-- The kinds of member activity the feed records: a class attendance, a rank
-- promotion (the member-detail progress anchor — see generators/activities.py),
-- or a video click.
CREATE TYPE member_activity_type AS ENUM (
    'class_attended', 'rank_changed', 'video_clicked'
);

CREATE TABLE member_activities (
    activity_id UUID NOT NULL DEFAULT uuid_generate_v4(),
    member_id UUID NOT NULL,
    gym_id UUID NOT NULL CONSTRAINT fk_activity_gym REFERENCES gyms(gym_id),
    activity_type member_activity_type NOT NULL,
    activity_info JSONB DEFAULT '{}',
    time TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (activity_id),
    CONSTRAINT fk_activity_member_gym
        FOREIGN KEY (member_id, gym_id)
        REFERENCES members (member_id, gym_id)
);
