-- VideoService gym-type templates (NOT the customer `gyms` table — these are the
-- 76 hand-authored demo gym templates keyed by a string id, e.g. 'boxing').
-- Authored as VideoService/gyms/<gym_id>.yaml; `make sync-gyms` upserts them here.

CREATE TABLE video_gym (
    gym_id TEXT NOT NULL
        CONSTRAINT video_gym_id_format CHECK (gym_id ~ '^[a-z0-9][a-z0-9_]*$'),
    -- The gym's discipline(s) as a JSONB string array; order is meaningful —
    -- gym_type[0] is the primary discipline the API derives parent_gym_type from.
    -- Values are validated against the discipline vocabulary by Pydantic on write.
    gym_type JSONB NOT NULL
        CONSTRAINT video_gym_type_nonempty
        CHECK (jsonb_typeof(gym_type) = 'array' AND jsonb_array_length(gym_type) >= 1),
    theme TEXT NOT NULL CONSTRAINT video_gym_theme_nonempty CHECK (theme <> ''),
    -- Spec is 1:1 with the gym, kept inline. The long pair is required (the scan
    -- judges against it); the short pair is display-only and optional until
    -- every gym is backfilled.
    short_videos_desc TEXT,
    short_avoid_desc TEXT,
    videos_desc TEXT NOT NULL
        CONSTRAINT video_gym_videos_desc_len CHECK (char_length(videos_desc) >= 2),
    avoid_desc TEXT NOT NULL
        CONSTRAINT video_gym_avoid_desc_len CHECK (char_length(avoid_desc) >= 2),
    -- Distinguishes "no classes authored" (NULL) from "authored, empty" so the
    -- API can reproduce GymDetail.classes == None exactly. sync-gyms sets these.
    has_classes BOOLEAN NOT NULL DEFAULT FALSE,
    has_rewards BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT pk_video_gym PRIMARY KEY (gym_id)
);
