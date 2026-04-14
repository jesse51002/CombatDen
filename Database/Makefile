
start:
	npx supabase start
	npx supabase migration up

migration: start
	npx supabase db diff --use-pg-delta -f $(name)
	npx supabase migration up

push:
	npx supabase db push

pull:
	npx supabase db pull


reset:
	npx supabase db reset

squash:
	npx supabase migration squash

stop:
	npx supabase stop --project-id GoApi

seed:
	python python_data/main.py