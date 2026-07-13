-- Hand-authored migration.
-- Every membership plan has an image now: a new membership_plans.image_url
-- (schemas/membership_plans.sql), mirroring gym_classes.image_url. The plan
-- card leans on it, so backend writers supply one at create time and NULL
-- never reaches the row going forward -- this migration just adds the column
-- and closes it off at the DB level to match. Small, additive: add the column
-- nullable, backfill any existing rows to a platform preset image, then add
-- the NOT NULL constraint. No table rebuild, no data loss.
--
-- The column lives on the base table membership_plans_unfiltered. The
-- membership_plans view is SELECT * over it, but Postgres freezes a view's
-- column list at CREATE time, so the view must be RECREATED to expose the
-- new column (the plans read path selects FROM the view — without the
-- recreate it keeps returning rows lacking image_url and the backend
-- KeyErrors). CREATE OR REPLACE works because image_url is appended as the
-- LAST base-table column; grants on the view are preserved.
-- security_invoker is re-stated both ways (the WITH clause and the ALTER),
-- mirroring schemas/membership_plans.sql — dropping it would silently
-- bypass RLS on the base table.

ALTER TABLE membership_plans_unfiltered
    ADD COLUMN image_url VARCHAR;

UPDATE membership_plans_unfiltered
SET image_url = 'https://cdn.combatden.net/membership/presets/activity-01.jpg'
WHERE image_url IS NULL;

ALTER TABLE membership_plans_unfiltered
    ALTER COLUMN image_url SET NOT NULL;

CREATE OR REPLACE VIEW membership_plans
WITH (security_invoker = true)
AS
SELECT * FROM membership_plans_unfiltered
WHERE stripe_product_id IS NOT NULL;

ALTER VIEW membership_plans SET (security_invoker = true);
