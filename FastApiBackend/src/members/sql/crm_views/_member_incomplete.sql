-- Canonical INCOMPLETE-SIGNUP derivation for the CRM members list.
--
-- Same shape and reasoning as _member_dormant.sql: a self-contained correlated
-- BOOLEAN expression, not a CTE, so the LIST filter (incomplete_view.sql) and
-- the TALLY (total_counts.sql) share ONE text and can never disagree about who
-- is incomplete. It joins its own members row, so the only thing it needs from
-- the outer query is the two id expressions supplied as the structural template
-- variables member_id/gym_id, and it binds no parameters.
--
-- A member is INCOMPLETE when ALL FOUR hold:
--   1. their row is VALID -- it has a stripe_customer_id, AND
--   2. they hold NO membership of their own, AND
--   3. they are NOT the payer on anyone else's membership, AND
--   4. they hold no BILLED-BUT-UNCONFIRMED non-recurring membership (as
--      subject or as payer).
--
-- Conditions 2 and 3 are the original rule and collapse into ONE NOT EXISTS: a
-- membership row disqualifies the member whether it names them as the SUBJECT
-- (member_id) or as the PAYER (paid_by_member_id). Condition 3 is the
-- load-bearing half of that pair. A non-training parent who pays for their kid
-- legitimately owns no membership themselves -- without the payer exclusion
-- they would sit in the staff "incomplete signups" list forever with nothing
-- left to finish, which is exactly the false positive that makes such a list
-- useless.
--
-- Deliberately NOT scoped to LIVE memberships. A member whose only membership
-- (or whose only payee's membership) has since been cancelled or ended is a
-- lapsed member, not an unfinished signup -- the list is for signups that never
-- completed, and re-listing a churned member here would bury the real ones.
--
-- CONDITION 1 -- a row with no stripe_customer_id is INVALID, not unfinished.
-- Every member is provisioned a Stripe customer at creation and the id is then
-- immutable (trg_prevent_stripe_customer_id_overwrite), so a NULL means the
-- create never completed and the row is a fragment of a failed write. It has no
-- billing identity, so nothing can be sold to it and the whole billing read
-- path (member_billing_profile filters on exactly this column) cannot see it.
-- Listing it as a signup to chase sends staff after a row that will reject
-- every next step. It should not be shown ANYWHERE.
--
-- CONDITION 4 -- billed-but-unconfirmed is a RECONCILIATION case, not a signup.
-- The start op charges the whole non-recurring group on one consolidated
-- invoice, then stamps each row applied. When the charge succeeds but that
-- writeback does not land, MemberMembershipsStart deliberately KEEPS the row
-- ("billed lines are never un-billed" -- memberships_start.py, _verify_group
-- with keep_unverified=True) in its pre-sync state: stripe_sync_status
-- 'not_added'. The member_memberships view hides exactly that status, so the
-- member reads to the whole CRM as owning nothing -- i.e. as an unfinished
-- signup -- when in fact their money has been taken. Chasing them to "finish"
-- is the worst possible follow-up, so they are excluded here; the fix they need
-- is reconciliation.
--
-- Scoped to NON-RECURRING plans on purpose, because that is the only group the
-- start op keeps: the recurring group is verified with keep_unverified=False and
-- an unconfirmed row is DELETED. So a surviving non-recurring 'not_added' row is
-- by construction a kept billed line, whereas a recurring one is either a
-- request in flight this second or a crash orphan the reconciler removes -- and
-- for those the documented behaviour below still holds. Only 'not_added' counts:
-- 'preview_add'/'preview_remove' rows are preview artifacts and were never
-- billed.
--
-- SOURCE TABLES: member_memberships_status (the FILTERED view -- Stripe-synced
-- rows only) for conditions 2/3, matching every other file in this folder;
-- member_memberships_unfiltered for condition 4, which is ABOUT a row the
-- filtered view hides and therefore cannot use it. A member mid-checkout on a
-- RECURRING plan still reads as incomplete until their purchase lands, which is
-- what staff should see.
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
