-- Canonical INCOMPLETE-SIGNUP derivation for the CRM members list.
--
-- Same shape as _member_dormant.sql: a self-contained correlated BOOLEAN, not
-- a CTE, so the LIST (incomplete_view.sql) and the TALLY (total_counts.sql)
-- share ONE text. It joins its own members row, needs only the two id
-- expressions injected as structural template variables, and binds nothing.
--
-- FOUR clauses, and each one keeps a specific WRONG person off a staff
-- follow-up list. Do not simplify one away:
--
-- 1. VALID row -- a NULL stripe_customer_id means the create never finished,
--    so the row has no billing identity and every next step staff could take
--    is rejected. Invalid, not unfinished: don't show it anywhere.
-- 2. Holds no membership of their own, AND
-- 3. is not the payer on anyone else's. The payer half is load-bearing: a
--    non-training parent paying for their kid legitimately owns no
--    membership, and without it would sit here forever with nothing to
--    finish.
-- 4. Holds no BILLED-BUT-UNCONFIRMED non-recurring membership (as subject or
--    payer). When a one-time group's invoice is PAID but the sync writeback
--    fails, MemberMembershipsStart deliberately KEEPS the row 'not_added'
--    ("billed lines are never un-billed") and the filtered view hides exactly
--    that status -- so the member reads as owning nothing while their card
--    has already been charged, and chasing them to "finish" is the worst
--    possible follow-up. NON-RECURRING only, because that is the only group
--    the start op keeps (an unconfirmed recurring row is deleted, so a
--    survivor is either in flight or a crash orphan the reconciler removes),
--    and 'not_added' only, because the preview statuses were never billed.
--
-- Deliberately NOT scoped to LIVE memberships: a member whose only membership
-- has since ended is a lapsed member, not an unfinished signup.
--
-- SOURCE TABLES: member_memberships_status (the FILTERED view) for 2/3, like
-- every other file in this folder; member_memberships_unfiltered for 4, which
-- is ABOUT a row the filtered view hides and therefore cannot use it.
EXISTS (
    SELECT 1
    FROM members icm
    WHERE icm.member_id = {member_id}
      AND icm.gym_id = {gym_id}
      -- 1. a valid row: it has a billing identity.
      AND icm.stripe_customer_id IS NOT NULL
      -- 2 + 3. owns nothing and funds nobody.
      AND NOT EXISTS (
          SELECT 1
          FROM member_memberships_status im
          WHERE im.gym_id = icm.gym_id
            AND (
                im.member_id = icm.member_id
                OR im.paid_by_member_id = icm.member_id
            )
      )
      -- 4. no kept billed line awaiting reconciliation.
      AND NOT EXISTS (
          SELECT 1
          FROM member_memberships_unfiltered ip
          JOIN membership_plans imp
              ON imp.plan_id = ip.plan_id
              AND imp.gym_id = ip.gym_id
          WHERE ip.gym_id = icm.gym_id
            AND (
                ip.member_id = icm.member_id
                OR ip.paid_by_member_id = icm.member_id
            )
            AND ip.stripe_sync_status = 'not_added'
            AND imp.plan_type <> 'recurring'
      )
)
