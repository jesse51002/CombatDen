-- Insert a gym's UNDELETABLE default authorized-payer waiver (is_default=true).
-- is_default is service_role-only (REVOKE'd from authenticated on INSERT), so
-- only the backend/seed creates it; idx_gym_waivers_one_default enforces <=1 per
-- gym. The version + current-version pointer are written by the same caller in
-- one transaction (see WaiversCreate._create).
INSERT INTO gym_waivers (gym_id, name, is_default)
VALUES (:gym_id, :name, true)
RETURNING *
