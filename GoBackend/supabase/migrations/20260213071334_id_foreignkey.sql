drop policy "Users can update own data" on "public"."users";

drop policy "Users can view own data" on "public"."users";

alter table "public"."users" drop constraint "users_pkey";

drop index if exists "public"."users_pkey";

alter table "public"."users" drop column "created_at";

alter table "public"."users" drop column "email";

alter table "public"."users" drop column "user_id";

alter table "public"."users" add column "id" uuid not null;

alter table "public"."users" add constraint "users_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) not valid;

alter table "public"."users" validate constraint "users_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
BEGIN
  INSERT INTO public.users (id)
  VALUES (NEW.id);
  RETURN NEW;
END;
$function$
;


  create policy "Users can update own data"
  on "public"."users"
  as permissive
  for update
  to public
using ((auth.uid() = id))
with check ((auth.uid() = id));



  create policy "Users can view own data"
  on "public"."users"
  as permissive
  for select
  to public
using ((auth.uid() = id));


CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


