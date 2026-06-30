-- The gym's memberships (every lifecycle state) for attendance attribution.
-- Reads the status view, so only real, fully-synced memberships surface (the
-- preview / not_added staging rows are excluded). The service picks ONE
-- membership per member (_eligible_attendees: prefer active, then most recent)
-- to pin each seeded attendance row's NOT-NULL plan_id + item_id. Attribution
-- is date-independent for this demo seed — the membership need NOT span the
-- occurrence's date — so past attendance spreads evenly across the month.
SELECT
    member_id,
    plan_id,
    item_id,
    start_date,
    end_date,
    cancel_date
FROM member_memberships_status
WHERE gym_id = CAST(:gym_id AS UUID)
