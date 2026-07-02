-- Idempotency (demo reset): hard-delete this gym's classes. Every dependent
-- (class_signups, member_attendance, class_instance_exceptions,
-- class_range_exceptions, gym_class_schedules) is wiped first, in FK-safe
-- order, by the sibling presets_delete_* files -- a re-import always starts
-- from a completely clean slate rather than soft-deleting + leaving stale
-- history behind (ghost past occurrences after a re-import are unacceptable
-- for demo data). "Which classes were imported" is identified the same way
-- the prior soft-delete used: every class belonging to this gym_id (a
-- preset-imported gym has no other classes).
DELETE FROM gym_classes WHERE gym_id = CAST(:gym_id AS UUID)
