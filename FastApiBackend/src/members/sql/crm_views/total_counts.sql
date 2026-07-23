-- Independent tallies, not a partition: a member can land in more than one
-- (an overdue member is also counted as active). The dormant tally follows
-- that same shape, and is counted straight off the members table because
-- dormancy is member-level -- one row per member, no membership join to
-- de-duplicate. The predicate is the shared one every dormant surface uses.
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
    ) AS dormant
FROM member_memberships_status m
JOIN membership_plans mp
    ON m.plan_id = mp.plan_id
    AND m.gym_id = mp.gym_id
JOIN gyms g ON g.gym_id = m.gym_id
WHERE m.gym_id = :gym_id
