-- One attendance row for a seeded occurrence, attributed to the member's pinned
-- membership plan_id/item_id. UNIQUE(member_id, class_history_id) holds: each
-- occurrence draws a DISTINCT subset of the eligible members against a
-- freshly-inserted class_history row, so no duplicate (member, occurrence) pair
-- is ever produced. Executed once per occurrence with a list of param rows.
INSERT INTO member_attendance (
    member_id, gym_id, class_history_id, plan_id, item_id
) VALUES (
    CAST(:member_id AS UUID),
    CAST(:gym_id AS UUID),
    CAST(:class_history_id AS UUID),
    CAST(:plan_id AS UUID),
    CAST(:item_id AS UUID)
)
