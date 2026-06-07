-- Save the calling employee's CRM appearance preference for one gym.
-- Scoped by (user_id from JWT, gym_id from the URL) so a caller can only
-- write their own row. theme_preference is the one client-editable column
-- (see immutable_columns.GYM_EMPLOYEES). CAST(... AS theme_mode) is required
-- because a bind parameter reaches Postgres as text, not the enum.
UPDATE gym_employees
SET theme_preference = CAST(:theme_preference AS theme_mode)
WHERE user_id = :user_id
  AND gym_id = :gym_id
RETURNING gym_id, theme_preference
