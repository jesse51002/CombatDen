-- Hand-authored migration.
-- Trainers have no accounts at all: a 'trainer' gym_employees row is
-- instructor DATA (a name/photo shown on classes), never a login
-- principal. This constraint makes is_gym_employee() (and every backend
-- staff check) owner/admin-only by construction.
--
-- Defensive backfill first, in case a stray linked trainer row exists,
-- so the CHECK can be added cleanly.

UPDATE gym_employees
SET user_id = NULL
WHERE employee_type = 'trainer' AND user_id IS NOT NULL;

ALTER TABLE gym_employees
    ADD CONSTRAINT chk_trainer_has_no_account
        CHECK (employee_type <> 'trainer' OR user_id IS NULL);
