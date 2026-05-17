-- View has security_invoker = true, so the underlying members +
-- member_status RLS policies apply. We only need to make sure
-- writes through the view are blocked (they're already nonsensical
-- for a SELECT view, but be explicit) and authenticated can read.
GRANT SELECT ON members_with_status TO authenticated;
REVOKE INSERT, UPDATE, DELETE ON members_with_status FROM authenticated;
