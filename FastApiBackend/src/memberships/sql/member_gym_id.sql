-- The gym a member belongs to (a member belongs to exactly one gym; gym_id is
-- immutable on members). The freeze/unfreeze path derives the gym server-side
-- from the member's own row instead of trusting a client-supplied gym_id
-- (C-070), so the profile write + payer discovery can never target another gym.
SELECT gym_id
FROM members
WHERE member_id = :member_id
