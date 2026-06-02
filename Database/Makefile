
start:
	npx supabase start
	npx supabase migration up

migration: start
	npx supabase db diff -f $(name)
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

# Fetch OpenAPI spec from local backend and format it with 2-space indentation
update-openapi:
	@echo "Fetching OpenAPI spec from http://localhost:8000/openapi.json..."
	@curl -s http://localhost:8000/openapi.json | python3 -m json.tool --indent 2 > openapi.json
	@echo "✓ OpenAPI spec updated and formatted in openapi.json"