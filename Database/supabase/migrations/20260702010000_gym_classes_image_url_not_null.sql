-- Hand-authored migration.
-- Every class has an image now: gym_classes.image_url moves from nullable to
-- NOT NULL (schemas/gym_classes.sql). Backend writers that receive no image
-- fill in the platform default (settings.default_class_image_url) before the
-- INSERT, so no application code path ever sends a NULL image_url going
-- forward -- this migration just closes the column off at the DB level to
-- match. Small, additive: backfill any existing NULLs to the same platform
-- default, then add the NOT NULL constraint. No table rebuild, no data loss.

UPDATE gym_classes
SET image_url = 'https://images.pexels.com/photos/1552242/pexels-photo-1552242.jpeg?auto=compress&cs=tinysrgb&w=1200'
WHERE image_url IS NULL;

ALTER TABLE gym_classes
    ALTER COLUMN image_url SET NOT NULL;
