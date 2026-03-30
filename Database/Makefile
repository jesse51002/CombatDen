
start:
	npx supabase start
	npx supabase migration up

migration: start
	npx supabase db diff -f $(name)
	npx supabase migration up

push:
	npx supabase db push

reset:
	npx supabase db reset

stop:
	npx supabase stop --project-id GoApi

seed:
	python python_data/main.py