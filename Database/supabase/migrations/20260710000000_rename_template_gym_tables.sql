-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Renames the 5 slug/text-keyed VideoService template-catalog tables from the
-- `video_gym*` prefix to `template_gym*`, plus every derived identifier, so the
-- live DB objects match the renamed schema files (schemas/template_gym*.sql,
-- access_rules/template_gym*.sql). This is a pure rename — no data, columns, RLS
-- policies, or FK targets change (policies and FK references follow their table
-- by OID). The UUID-keyed PROD tables (gym_video_spec / gym_video_feed /
-- gym_classes / gym_rewards) and the video.gym_id custom-ownership column
-- (video's fk_video_gym / idx_video_gym) are deliberately untouched.
--
-- Mirrors schemas/template_gym.sql, template_gym_query.sql, template_gym_class.sql,
-- template_gym_reward.sql, template_gym_feed.sql and their access_rules.
--
-- Order: rename the enum type, then the tables, then each table's constraints
-- (referenced by their new table name), then the plain btree indexes. A PK/UNIQUE
-- constraint and its backing index share one identity in Postgres, so renaming the
-- constraint renames its index too — only the standalone CREATE INDEX btrees are
-- renamed explicitly below.

-- 1. Enum type (the template_gym_feed.status type)
ALTER TYPE video_gym_feed_status RENAME TO template_gym_feed_status;

-- 2. Tables (parent first, then children — cosmetic; RENAME has no FK ordering
--    requirement since references follow by OID)
ALTER TABLE video_gym RENAME TO template_gym;
ALTER TABLE video_gym_query RENAME TO template_gym_query;
ALTER TABLE video_gym_class RENAME TO template_gym_class;
ALTER TABLE video_gym_reward RENAME TO template_gym_reward;
ALTER TABLE video_gym_feed RENAME TO template_gym_feed;

-- 3. Constraints (PK + CHECK + FK), keyed by the now-renamed table names
-- template_gym
ALTER TABLE template_gym RENAME CONSTRAINT pk_video_gym TO pk_template_gym;
ALTER TABLE template_gym RENAME CONSTRAINT video_gym_id_format TO template_gym_id_format;
ALTER TABLE template_gym RENAME CONSTRAINT video_gym_type_nonempty TO template_gym_type_nonempty;
ALTER TABLE template_gym RENAME CONSTRAINT video_gym_theme_nonempty TO template_gym_theme_nonempty;
ALTER TABLE template_gym RENAME CONSTRAINT video_gym_videos_desc_len TO template_gym_videos_desc_len;
ALTER TABLE template_gym RENAME CONSTRAINT video_gym_avoid_desc_len TO template_gym_avoid_desc_len;

-- template_gym_query
ALTER TABLE template_gym_query RENAME CONSTRAINT pk_video_gym_query TO pk_template_gym_query;
ALTER TABLE template_gym_query RENAME CONSTRAINT fk_video_gym_query_gym TO fk_template_gym_query_gym;
ALTER TABLE template_gym_query RENAME CONSTRAINT video_gym_query_nonempty TO template_gym_query_nonempty;

-- template_gym_class
ALTER TABLE template_gym_class RENAME CONSTRAINT pk_video_gym_class TO pk_template_gym_class;
ALTER TABLE template_gym_class RENAME CONSTRAINT fk_video_gym_class_gym TO fk_template_gym_class_gym;
ALTER TABLE template_gym_class RENAME CONSTRAINT video_gym_class_name_nonempty TO template_gym_class_name_nonempty;
ALTER TABLE template_gym_class RENAME CONSTRAINT video_gym_class_image_url_nonempty TO template_gym_class_image_url_nonempty;
ALTER TABLE template_gym_class RENAME CONSTRAINT video_gym_class_description_nonempty TO template_gym_class_description_nonempty;
ALTER TABLE template_gym_class RENAME CONSTRAINT video_gym_class_instructor_name_nonempty TO template_gym_class_instructor_name_nonempty;
ALTER TABLE template_gym_class RENAME CONSTRAINT video_gym_class_instructor_bio_nonempty TO template_gym_class_instructor_bio_nonempty;
ALTER TABLE template_gym_class RENAME CONSTRAINT video_gym_class_instructor_image_url_nonempty TO template_gym_class_instructor_image_url_nonempty;

-- template_gym_reward
ALTER TABLE template_gym_reward RENAME CONSTRAINT pk_video_gym_reward TO pk_template_gym_reward;
ALTER TABLE template_gym_reward RENAME CONSTRAINT fk_video_gym_reward_gym TO fk_template_gym_reward_gym;
ALTER TABLE template_gym_reward RENAME CONSTRAINT video_gym_reward_title_nonempty TO template_gym_reward_title_nonempty;
ALTER TABLE template_gym_reward RENAME CONSTRAINT video_gym_reward_image_url_nonempty TO template_gym_reward_image_url_nonempty;
ALTER TABLE template_gym_reward RENAME CONSTRAINT video_gym_reward_price_label_nonempty TO template_gym_reward_price_label_nonempty;
ALTER TABLE template_gym_reward RENAME CONSTRAINT video_gym_reward_points_cost_nonneg TO template_gym_reward_points_cost_nonneg;

-- template_gym_feed
ALTER TABLE template_gym_feed RENAME CONSTRAINT pk_video_gym_feed TO pk_template_gym_feed;
ALTER TABLE template_gym_feed RENAME CONSTRAINT fk_video_gym_feed_gym TO fk_template_gym_feed_gym;
ALTER TABLE template_gym_feed RENAME CONSTRAINT fk_video_gym_feed_video TO fk_template_gym_feed_video;

-- 4. Indexes. A PK/UNIQUE constraint and its backing index share one identity in
--    Postgres, so the RENAME CONSTRAINT calls above ALREADY renamed the pk_*
--    backing indexes (pk_video_gym -> pk_template_gym, etc.) — renaming them again
--    here would error on the now-missing old name. Only the plain CREATE INDEX
--    btrees (not constraint-backed) still carry the old prefix and need renaming.
ALTER INDEX idx_video_gym_query_gym RENAME TO idx_template_gym_query_gym;
ALTER INDEX idx_video_gym_class_gym RENAME TO idx_template_gym_class_gym;
ALTER INDEX idx_video_gym_reward_gym RENAME TO idx_template_gym_reward_gym;
ALTER INDEX idx_video_gym_feed_serve RENAME TO idx_template_gym_feed_serve;
