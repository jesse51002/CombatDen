-- One attendance row for a seeded occurrence, attributed to the member's
-- pinned membership plan_id/item_id. Occurrence identity = (class_id,
-- original_date, original_time) -- the schedule version's slot before
-- exceptions (this import never writes exceptions, so original_time always
-- equals the resolved slot's scheduled time). occurred_at is the
-- denormalized effective UTC start instant (the expander's output,
-- unaffected by exceptions here). UNIQUE(member_id, class_id, original_date,
-- original_time) holds: each occurrence draws a DISTINCT subset of the
-- eligible members against a freshly re-seeded window, so no duplicate
-- (member, occurrence) pair is ever produced. Executed once per occurrence
-- with a list of param rows.
INSERT INTO member_attendance (
    member_id, gym_id, class_id, original_date, original_time, occurred_at,
    plan_id, item_id
) VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:class_id AS UUID),
    CAST(:original_date AS DATE),
    CAST(:original_time AS TIME),
    CAST(:occurred_at AS TIMESTAMPTZ),
    CAST(:plan_id AS UUID),
    CAST(:item_id AS UUID)
)
