-- Count of memberships that are active (INCLUDING frozen) as of a single
-- gym-local date. Copies the date operators of the member_memberships_status
-- view with the view's gym-local "today" replaced by the bound date: a
-- membership is 'cancelled' when cancel_date <= the date and 'ended' when
-- end_date <= the date, so anything not cancelled and not ended is active. The
-- freeze window is NOT stored historically, so a currently-frozen membership
-- counts as active here (matching the view's ELSE 'active' fall-through for the
-- non-terminal case). Reads the filtered member_memberships view.
--
-- DELIBERATE DEVIATION from the pure view-copy: the view has no start-date
-- gate because it derives status for the CURRENT date, where a future-start
-- row genuinely exists "now". This is an AS-OF-the-bound-date HISTORICAL
-- count, so a membership that had not started by the as-of date must NOT be
-- counted -- hence the extra start-date bound below.
SELECT COUNT(*) AS active_count
FROM member_memberships mm
WHERE mm.gym_id = CAST(:gym_id AS UUID)
  AND mm.start_date <= CAST(:as_of_date AS DATE)
  AND (mm.cancel_date IS NULL OR mm.cancel_date > CAST(:as_of_date AS DATE))
  AND (mm.end_date IS NULL OR mm.end_date > CAST(:as_of_date AS DATE))
