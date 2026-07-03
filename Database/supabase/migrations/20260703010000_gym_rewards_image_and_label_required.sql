-- Hand-authored migration.
-- Every reward has an image and a value badge now: gym_rewards.image_url and
-- gym_rewards.price_label move from nullable to NOT NULL (schemas/gym_rewards.sql),
-- mirroring 20260702010000_gym_classes_image_url_not_null.sql for gym_classes.
-- Backend writers that receive no image fill in the platform default
-- (settings.default_reward_image_url) before the INSERT, and price_label is
-- now a required create-request field, so no application code path ever
-- sends a NULL for either column going forward -- this migration just closes
-- both columns off at the DB level to match. Small, additive: backfill any
-- existing NULLs, then add the NOT NULL constraints. No table rebuild, no
-- data loss.

UPDATE gym_rewards
SET image_url = 'https://images.pexels.com/photos/5493207/pexels-photo-5493207.jpeg?auto=compress&cs=tinysrgb&w=1200'
WHERE image_url IS NULL;

UPDATE gym_rewards
SET price_label = 'Free'
WHERE price_label IS NULL;

ALTER TABLE gym_rewards
    ALTER COLUMN image_url SET NOT NULL;

ALTER TABLE gym_rewards
    ALTER COLUMN price_label SET NOT NULL;
