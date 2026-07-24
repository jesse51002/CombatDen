-- Canonical INCOMPLETE-SIGNUP derivation for the CRM members list.
--
-- Same shape and reasoning as _member_dormant.sql: a self-contained correlated
-- BOOLEAN expression, not a CTE, so the LIST filter (incomplete_view.sql) and
-- the TALLY (total_counts.sql) share ONE text and can never disagree about who
-- is incomplete. It joins nothing from the outer query except the two id
-- expressions supplied as the structural template variables member_id/gym_id,
-- and it binds no parameters.
--
-- A member is INCOMPLETE when BOTH hold:
--   1. they hold NO membership of their own, AND
--   2. they are NOT the payer on anyone else's membership.
--
-- Condition 2 is the load-bearing half. A non-training parent who pays for
-- their kid legitimately owns no membership themselves — without the payer
-- exclusion they would sit in the staff "incomplete signups" list forever with
-- nothing left to finish, which is exactly the false positive that makes such a
-- list useless. Both halves collapse into ONE NOT EXISTS: a membership row
-- disqualifies the member whether it names them as the SUBJECT (member_id) or
-- as the PAYER (paid_by_member_id).
--
-- Deliberately NOT scoped to LIVE memberships. A member whose only membership
-- (or whose only payee's membership) has since been cancelled or ended is a
-- lapsed member, not an unfinished signup — the list is for signups that never
-- completed, and re-listing a churned member here would bury the real ones.
--
-- SOURCE TABLE: member_memberships_status (the FILTERED view — Stripe-synced
-- rows only), matching every other file in this folder. A half-written
-- `not_added` row from an in-flight purchase is invisible to the whole CRM, so
-- a member mid-checkout still reads as incomplete until their purchase lands,
-- which is what staff should see.
NOT EXISTS (
    SELECT 1
    FROM member_memberships_status im
    WHERE im.gym_id = {gym_id}
      AND (
          im.member_id = {member_id}
          OR im.paid_by_member_id = {member_id}
      )
)
