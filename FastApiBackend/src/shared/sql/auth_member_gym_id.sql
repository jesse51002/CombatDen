-- Resolve a member's owning gym so a member-scoped route can run the
-- gym-scoped employee check against it. This is a pure lookup, NOT an
-- identity resolution — the caller's verified-account predicate is applied
-- by the gym-scoped check that follows (auth_resolve_employee.sql).
SELECT m.gym_id
FROM members m
WHERE m.member_id = CAST(:member_id AS UUID)
LIMIT 1;
