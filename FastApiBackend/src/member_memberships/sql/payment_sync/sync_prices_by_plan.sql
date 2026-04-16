-- Resolve each Stripe invoice line to a plan_id via
-- membership_plan_prices, sum amounts per plan, and write that
-- plan-level post-discount total onto every member_memberships row
-- in the paying family on that plan.
--
-- Scoping lives in crm_user_id = ANY(family_ids) so other families
-- on the same plan_id are never touched. Any input line whose
-- stripe_price_id has no matching CRM price is silently dropped by
-- the INNER JOIN; a later sync will re-attempt.
--
-- NB: cast(param AS type) is used instead of the shorthand cast
-- syntax because SQLAlchemy text() will not match a bind parameter
-- when it is immediately followed by a double-colon cast operator.
WITH input AS (
    SELECT
        (elem ->> 'stripe_price_id')::text AS stripe_price_id,
        (elem ->> 'amount')::int           AS amount
    FROM jsonb_array_elements(cast(:line_amounts AS jsonb)) AS elem
),
plan_totals AS (
    SELECT mpp.plan_id, SUM(i.amount) AS plan_total
    FROM input i
    JOIN membership_plan_prices mpp
      ON mpp.stripe_price_id = i.stripe_price_id
    GROUP BY mpp.plan_id
)
UPDATE member_memberships_unfiltered mm
SET total_price = pt.plan_total
FROM plan_totals pt
WHERE mm.plan_id = pt.plan_id
  AND mm.crm_user_id = ANY(cast(:family_ids AS uuid[]))
