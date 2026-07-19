-- HAND-AUTHORED migration (not `supabase db diff` output).
-- Adds the 'front_desk' value to employee_type, appended LAST so its ordinal
-- matches schemas/gyms.sql. Kept in its own file (committed before
-- 20260711010001_employees_email_identity.sql runs) because PG12+ only
-- allows ALTER TYPE ... ADD VALUE inside a transaction when the new value is
-- not USED in that same transaction — this migration never references
-- 'front_desk', so it's technically safe either way, but the split keeps the
-- enum-growth step isolated on principle (mirrors
-- 20260703000001_video_worker_rag.sql's gym_video_scan_status 'pending' add).
--
-- Mirrors schemas/gyms.sql.

ALTER TYPE employee_type ADD VALUE IF NOT EXISTS 'front_desk';
