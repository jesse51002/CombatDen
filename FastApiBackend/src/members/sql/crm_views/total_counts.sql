-- Independent tallies, not a partition: a member can land in more than one
-- (an overdue member is also counted as active). The dormant and incomplete
-- tallies follow that same shape, and are counted straight off the members
-- table because both rules are member-level -- one row per member, no
-- membership join to de-duplicate. Each predicate is the shared one its own
-- surface uses (_member_dormant.sql / _member_incomplete.sql).
--
-- incomplete is the one tally that CANNOT overlap the others: it counts
-- members with no membership at all, and every other tally requires one.
--
-- The tally applies the RULE; the badge additionally applies a precedence
-- (see DORMANT_YIELDS_TO in members_status_mapping), so a dormant member
-- whose membership is frozen or past due is counted here while their badge
-- shows frozen / overdue instead. Rare and deliberate -- the alternative is
-- an aggregate that has to guess which membership row wins the badge.
SELECT
    COUNT(DISTINCT m.member_id) FILTER (
        WHERE m.status = 'active'
        AND mp.plan_type != 'trial'
    ) AS active,
    COUNT(DISTINCT m.member_id) FILTER (
        WHERE mp.plan_type = 'trial'
        AND m.status = 'active'
    ) AS trial,
    COUNT(DISTINCT m.member_id) FILTER (
        WHERE m.status = 'frozen'
    ) AS frozen,
    COUNT(DISTINCT m.member_id) FILTER (
        -- Match the Overdue tab (overdue_view.sql) and the row badge
        -- (is_membership_overdue): a cancelled membership keeps its stale
        -- past next_due_date forever, so without this guard the subtitle
        -- count drifts permanently above what the Overdue tab lists.
        WHERE m.status != 'cancelled'
        AND m.next_due_date < (now() AT TIME ZONE g.timezone)::date
    ) AS overdue,
    (
        SELECT count(*)
        FROM members dormant_m
        WHERE dormant_m.gym_id = :gym_id
        AND {is_dormant}
    ) AS dormant,
    -- Incomplete signups. Counted straight off the members table for the same
    -- reason as dormant: the rule is member-level (no membership of their own
    -- AND not paying for anyone), so it cannot be expressed by FILTERing the
    -- membership-joined scan above — a member with no memberships contributes
    -- no row to it at all. The predicate is the shared one the Incomplete tab
    -- lists with (_member_incomplete.sql).
    (
        SELECT count(*)
        FROM members incomplete_m
        WHERE incomplete_m.gym_id = :gym_id
        AND {is_incomplete}
    ) AS incomplete
FROM member_memberships_status m
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON g.gym_id = m.gym_id
WHERE m.gym_id = :gym_id
