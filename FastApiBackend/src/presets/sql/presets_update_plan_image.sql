-- Overwrite one membership plan's image_url with an imported class photo.
--
-- Writes the base membership_plans_unfiltered table (the membership_plans
-- view is read-only), matching every other plan write -- see
-- src/plans/sql/membership_plans_update.sql. Scoped by gym_id + plan_id +
-- is_deleted = false, so a soft-deleted plan is never touched even if its id
-- were somehow passed. image_url is NOT NULL on the table and only real,
-- post-fallback imported class URLs are ever bound here.
UPDATE membership_plans_unfiltered
SET image_url = :image_url
WHERE plan_id = CAST(:plan_id AS UUID)
  AND gym_id = CAST(:gym_id AS UUID)
  AND is_deleted = false
