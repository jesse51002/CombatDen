-- Per-membership paid_by_member_id: the member who PAYS each membership (the
-- resolved parent, or a self-paying linked member). Immutable; the payment sync
-- groups by it (one subscription per payer). Also: drop linked_account_no_stripe
-- so a linked member may hold their own billing state, and re-key the membership
-- status view's freeze owner to the PAYER.
--
-- HAND-AUTHORED, not `supabase db diff` output: db diff regenerated this as a
-- destructive migration (revoked every grant from service_role/anon/authenticated
-- and stripped `security_invoker` off the recreated views — a grant + RLS-bypass
-- regression). This migration carries ONLY the real schema delta; the `schemas/`
-- files remain the source of truth.

-- Drop the dependent views first (status depends on the memberships view); both
-- are recreated below to carry paid_by_member_id.
drop view if exists "public"."member_memberships_status";
drop view if exists "public"."member_memberships";

-- A linked member may now self-pay (their own customer / card / freeze window),
-- so the constraint that forbade billing state on a linked account is gone.
alter table "public"."members" drop constraint "linked_account_no_stripe";

-- The payer column + its partial index, FKs, and immutability trigger.
alter table "public"."member_memberships_unfiltered" add column "paid_by_member_id" uuid not null;

CREATE INDEX idx_member_memberships_paid_by ON public.member_memberships_unfiltered USING btree (paid_by_member_id) WHERE (cancel_date IS NULL);

alter table "public"."member_memberships_unfiltered" add constraint "fk_membership_payer" FOREIGN KEY (paid_by_member_id) REFERENCES public.members(member_id) not valid;
alter table "public"."member_memberships_unfiltered" validate constraint "fk_membership_payer";

alter table "public"."member_memberships_unfiltered" add constraint "fk_membership_payer_gym" FOREIGN KEY (paid_by_member_id, gym_id) REFERENCES public.members(member_id, gym_id) not valid;
alter table "public"."member_memberships_unfiltered" validate constraint "fk_membership_payer_gym";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.prevent_paid_by_member_id_overwrite()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    IF NEW.paid_by_member_id IS DISTINCT FROM OLD.paid_by_member_id THEN
        RAISE EXCEPTION 'paid_by_member_id cannot be changed after creation'
            USING CONSTRAINT = 'paid_by_member_id_immutable';
    END IF;
    RETURN NEW;
END;
$function$
;

-- Recreate the client-facing membership view with paid_by_member_id.
-- security_invoker MUST be preserved (db diff strips it; the schema file warns
-- of exactly this) or the view bypasses RLS.
create or replace view "public"."member_memberships" as  SELECT item_id,
    member_id,
    gym_id,
    plan_id,
    price_id,
    paid_by_member_id,
    start_date,
    end_date,
    cancel_date,
    last_paid_date,
    next_due_date,
    stripe_item_id,
    stripe_one_time_invoice_id,
    prorate,
    total_price,
    stripe_sync_status,
    created_at
   FROM public.member_memberships_unfiltered
  WHERE ((stripe_item_id IS NOT NULL) AND (stripe_sync_status <> ALL (ARRAY['not_added'::public.stripe_sync_status, 'preview_add'::public.stripe_sync_status, 'preview_remove'::public.stripe_sync_status])));

alter view "public"."member_memberships" set (security_invoker = true);

-- Recreate the status view: freeze is now per PAYER — the freeze owner joins on
-- paid_by_member_id (not COALESCE(account_linked_to_id, member_id)).
create or replace view "public"."member_memberships_status" as  SELECT mm.item_id,
    mm.member_id,
    mm.gym_id,
    mm.plan_id,
    mm.price_id,
    mm.paid_by_member_id,
    mm.start_date,
    mm.end_date,
    mm.cancel_date,
    mm.last_paid_date,
    mm.next_due_date,
    mm.stripe_item_id,
    mm.stripe_one_time_invoice_id,
    mm.prorate,
    mm.total_price,
    mm.stripe_sync_status,
    mm.created_at,
    freeze_owner.freeze_start_date,
    freeze_owner.freeze_end_date,
        CASE
            WHEN ((mm.cancel_date IS NOT NULL) AND (mm.cancel_date <= ((now() AT TIME ZONE g.timezone))::date)) THEN 'cancelled'::text
            WHEN ((mm.end_date IS NOT NULL) AND (mm.end_date <= ((now() AT TIME ZONE g.timezone))::date)) THEN 'ended'::text
            WHEN ((freeze_owner.freeze_start_date IS NOT NULL) AND (freeze_owner.freeze_end_date IS NOT NULL) AND (freeze_owner.freeze_start_date <= ((now() AT TIME ZONE g.timezone))::date) AND (((now() AT TIME ZONE g.timezone))::date <= freeze_owner.freeze_end_date)) THEN 'frozen'::text
            ELSE 'active'::text
        END AS status
   FROM ((public.member_memberships mm
     JOIN public.gyms g ON ((g.gym_id = mm.gym_id)))
     JOIN public.members freeze_owner ON ((freeze_owner.member_id = mm.paid_by_member_id)));

alter view "public"."member_memberships_status" set (security_invoker = true);

CREATE TRIGGER trg_prevent_paid_by_member_id_overwrite BEFORE UPDATE OF paid_by_member_id ON public.member_memberships_unfiltered FOR EACH ROW EXECUTE FUNCTION public.prevent_paid_by_member_id_overwrite();
