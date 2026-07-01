-- Idempotency (demo reset): wipe this gym's sign-up reservations before
-- re-seeding. A re-import mints brand-new class_id values (the prior classes
-- are only soft-deleted, never removed -- see presets_soft_delete_classes.sql),
-- so without this the old reservations would linger, pinned to a now
-- soft-deleted class, instead of being replaced by a clean re-seed. No FK
-- ordering constraint against class_history/member_attendance -- class_signups
-- references only gym_classes and members, both of which still exist.
DELETE FROM class_signups WHERE gym_id = CAST(:gym_id AS UUID)
