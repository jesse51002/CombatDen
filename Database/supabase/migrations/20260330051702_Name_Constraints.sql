alter table "public"."gym_discounts" drop constraint "gym_discounts_gym_id_fkey";

alter table "public"."gym_history" drop constraint "gym_history_gym_id_fkey";

alter table "public"."gym_rewards" drop constraint "gym_rewards_gym_id_fkey";

alter table "public"."gyms" drop constraint "gyms_owner_id_fkey";

alter table "public"."member_memberships" drop constraint "member_memberships_crm_user_id_gym_id_fkey";

alter table "public"."member_memberships" drop constraint "member_memberships_gym_id_fkey";

alter table "public"."member_memberships" drop constraint "member_memberships_plan_id_gym_id_fkey";

alter table "public"."membership_plans" drop constraint "membership_plans_gym_id_fkey";

alter table "public"."user_activities" drop constraint "user_activities_crm_user_id_gym_id_fkey";

alter table "public"."user_activities" drop constraint "user_activities_gym_id_fkey";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_account_linked_to_id_gym_id_fkey";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_gym_id_fkey";

alter table "public"."user_gym_profiles" drop constraint "user_gym_profiles_user_id_fkey";

alter table "public"."user_gym_transactions" drop constraint "user_gym_transactions_crm_user_id_gym_id_fkey";

alter table "public"."user_gym_transactions" drop constraint "user_gym_transactions_gym_id_fkey";

alter table "public"."gyms" drop constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" drop constraint "member_memberships_status_check";

CREATE UNIQUE INDEX user_gym_profiles_user_id_gym_id_key ON public.user_gym_profiles USING btree (user_id, gym_id);

alter table "public"."gym_discounts" add constraint "fk_discount_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_discounts" validate constraint "fk_discount_gym";

alter table "public"."gym_history" add constraint "fk_history_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_history" validate constraint "fk_history_gym";

alter table "public"."gym_rewards" add constraint "fk_reward_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."gym_rewards" validate constraint "fk_reward_gym";

alter table "public"."gyms" add constraint "fk_gyms_owner" FOREIGN KEY (owner_id) REFERENCES auth.users(id) not valid;

alter table "public"."gyms" validate constraint "fk_gyms_owner";

alter table "public"."member_memberships" add constraint "fk_membership_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_gym";

alter table "public"."member_memberships" add constraint "fk_membership_plan_gym" FOREIGN KEY (plan_id, gym_id) REFERENCES public.membership_plans(plan_id, gym_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_plan_gym";

alter table "public"."member_memberships" add constraint "fk_membership_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."member_memberships" validate constraint "fk_membership_profile_gym";

alter table "public"."membership_plans" add constraint "fk_plan_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."membership_plans" validate constraint "fk_plan_gym";

alter table "public"."user_activities" add constraint "fk_activity_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_activities" validate constraint "fk_activity_gym";

alter table "public"."user_activities" add constraint "fk_activity_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_activities" validate constraint "fk_activity_profile_gym";

alter table "public"."user_gym_profiles" add constraint "fk_profile_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_gym";

alter table "public"."user_gym_profiles" add constraint "fk_profile_linked_account_same_gym" FOREIGN KEY (account_linked_to_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_linked_account_same_gym";

alter table "public"."user_gym_profiles" add constraint "fk_profile_user" FOREIGN KEY (user_id) REFERENCES auth.users(id) not valid;

alter table "public"."user_gym_profiles" validate constraint "fk_profile_user";

alter table "public"."user_gym_profiles" add constraint "user_gym_profiles_user_id_gym_id_key" UNIQUE using index "user_gym_profiles_user_id_gym_id_key";

alter table "public"."user_gym_transactions" add constraint "fk_transaction_gym" FOREIGN KEY (gym_id) REFERENCES public.gyms(gym_id) not valid;

alter table "public"."user_gym_transactions" validate constraint "fk_transaction_gym";

alter table "public"."user_gym_transactions" add constraint "fk_transaction_profile_gym" FOREIGN KEY (crm_user_id, gym_id) REFERENCES public.user_gym_profiles(crm_user_id, gym_id) not valid;

alter table "public"."user_gym_transactions" validate constraint "fk_transaction_profile_gym";

alter table "public"."gyms" add constraint "gyms_rank_preset_check" CHECK (((rank_preset)::text = ANY ((ARRAY['bjj'::character varying, 'muay_thai'::character varying, 'karate'::character varying, 'taekwondo'::character varying, 'judo'::character varying, 'mma'::character varying])::text[]))) not valid;

alter table "public"."gyms" validate constraint "gyms_rank_preset_check";

alter table "public"."member_memberships" add constraint "member_memberships_status_check" CHECK (((status)::text = ANY ((ARRAY['active'::character varying, 'frozen'::character varying, 'cancelled'::character varying])::text[]))) not valid;

alter table "public"."member_memberships" validate constraint "member_memberships_status_check";


