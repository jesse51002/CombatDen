-- Hand-authored migration.
-- Attendance: membership attribution becomes optional, reaching the schemas/
-- end state for member_attendance.
--   * plan_id and item_id drop NOT NULL — an admin (non-kiosk) check-in records
--     even when the member has NO covering membership, leaving both NULL (no pack
--     is drawn; cycle-count / streak reads ignore NULL-membership rows).
--   * New CONSTRAINT chk_attendance_membership_pair CHECK ((plan_id IS NULL) =
--     (item_id IS NULL)) keeps the pair coherent: both set (covered) or both NULL
--     (no-membership admin check-in).
-- The composite FKs (fk_attendance_plan_gym, fk_attendance_membership_member) stay
-- as-is: they use MATCH SIMPLE (the Postgres default), so a row with a NULL in any
-- referencing column skips the FK check entirely — no FK change is needed.
-- No view selects from member_attendance, so no view recreation is needed.

ALTER TABLE member_attendance ALTER COLUMN plan_id DROP NOT NULL;
ALTER TABLE member_attendance ALTER COLUMN item_id DROP NOT NULL;

ALTER TABLE member_attendance
    ADD CONSTRAINT chk_attendance_membership_pair
    CHECK ((plan_id IS NULL) = (item_id IS NULL));
