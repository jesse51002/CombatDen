-- Insert a gym's UNDELETABLE payer-auth waiver (waiver_type='payer_auth').
-- waiver_type is service_role-only (REVOKE'd from authenticated on INSERT), so
-- only the backend/seed creates it; idx_gym_waivers_one_payer_auth enforces <=1
-- per gym. The version + current-version pointer are written by the same caller
-- in one transaction (see WaiversCreate._create).
INSERT INTO gym_waivers (gym_id, name, waiver_type)
VALUES (:gym_id, :name, 'payer_auth')
RETURNING *
