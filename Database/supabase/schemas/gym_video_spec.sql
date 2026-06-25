-- A real customer gym's live video spec — one row per gym. This is the PRODUCTION
-- counterpart of the slug-keyed `video_gym` template catalog: `video_gym*` holds
-- the 76 hand-authored templates the preset import copies FROM; the `gym_video_*`
-- tables hold what a real gym (gyms.gym_id UUID) actually serves. The long
-- videos_desc/avoid_desc pair is the scan criteria the (separate) batch job judges
-- candidates against; the short pair is display-only. `imported_from` records the
-- template slug a preset import seeded this row from (NULL once hand-edited).

CREATE TABLE gym_video_spec (
    gym_id UUID NOT NULL
        CONSTRAINT pk_gym_video_spec PRIMARY KEY
        CONSTRAINT fk_gym_video_spec_gym REFERENCES gyms(gym_id) ON DELETE CASCADE,
    -- The gym's discipline(s) as a JSONB string array; gym_type[0] is primary.
    gym_type JSONB NOT NULL DEFAULT '[]'
        CONSTRAINT gym_video_spec_type_is_array CHECK (jsonb_typeof(gym_type) = 'array'),
    short_videos_desc TEXT,
    short_avoid_desc TEXT,
    videos_desc TEXT NOT NULL DEFAULT '',
    avoid_desc TEXT NOT NULL DEFAULT '',
    -- Provenance: the video_gym template slug a preset import copied this from.
    imported_from TEXT,
    imported_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
