-- Hand-authored migration.
-- Every membership plan has an image now: a new membership_plans.image_url
-- (schemas/membership_plans.sql), mirroring gym_classes.image_url. The plan
-- card leans on it, so backend writers supply one at create time and NULL
-- never reaches the row going forward -- this migration just adds the column
-- and closes it off at the DB level to match. Small, additive: add the column
-- nullable, backfill any existing rows to a platform preset image, then add
-- the NOT NULL constraint. No table rebuild, no data loss.
--
-- The column lives on the base table membership_plans_unfiltered; the
-- membership_plans view is SELECT * over it, so image_url flows through the
-- view automatically (no view recreate needed).

ALTER TABLE membership_plans_unfiltered
    ADD COLUMN image_url VARCHAR;

UPDATE membership_plans_unfiltered
SET image_url = 'https://cdn.combatden.net/membership/presets/activity-01.jpg'
WHERE image_url IS NULL;

ALTER TABLE membership_plans_unfiltered
    ALTER COLUMN image_url SET NOT NULL;
