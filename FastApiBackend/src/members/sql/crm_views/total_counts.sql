-- Independent tallies, not a partition: a member can land in more than one
-- (an overdue member is also counted as active). The dormant and incomplete
-- tallies are counted straight off the members table because both rules are
-- member-level -- one row per member, no membership join to de-duplicate.
-- Each predicate is the shared one its own surface uses. incomplete is the
-- one tally that cannot overlap the others: it counts members with no
-- membership at all, and every other tally requires one.
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
    (
        -- Counted as its own deduped subquery, NOT as a FILTER over the
        -- outer FROM, so this tally lists exactly what the Overdue tab
        -- (overdue_view.sql) shows. Two things have to match, and both
        -- live here rather than in the outer query so the other tallies
        -- (active / trial / frozen) keep their undeduped semantics:
        --   1. the DISTINCT ON -- newest membership per (member, plan),
        --      identical to the tab's latest_memberships CTE. Without it
        --      a member holding an old past-due row AND a newer current
        --      row on the same plan is counted here but absent there.
        --   2. the shared overdue predicate.
        SELECT count(DISTINCT lm.member_id)
        FROM (
            SELECT DISTINCT ON (member_id, gym_id, plan_id) *
            FROM member_memberships_status
            WHERE gym_id = :gym_id
            ORDER BY member_id, gym_id, plan_id,
                     start_date DESC, created_at DESC
        ) lm
        JOIN gyms lg ON lg.gym_id = lm.gym_id
        WHERE ({is_overdue})
    ) AS overdue,
    (
        SELECT count(*)
        FROM members dormant_m
        WHERE dormant_m.gym_id = :gym_id
        AND {is_dormant}
    ) AS dormant,
    -- Incomplete signups. Cannot be expressed by FILTERing the
    -- membership-joined scan above -- a member with no memberships
    -- contributes no row to it at all. Shared predicate, so the tab and the
    -- tally cannot disagree.
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
