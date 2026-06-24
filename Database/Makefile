
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
	npx supabase stop --project-id Gymworld

seed:
	python python_data/main.py
	# VideoService keys on its own video_gym ids in a SEPARATE DB, so seeding the
	# main DB leaves the video_* tables empty → every video surface 404s ("video
	# service unreachable", blank CRM video tabs). Sync the whole video catalog so
	# those surfaces populate. Targets VideoService's local .env DB.
	$(MAKE) -C ../VideoService sync GYM_ID=all

# Fetch OpenAPI spec from local backend and format it with 2-space indentation
update-openapi:
	@echo "Fetching OpenAPI spec from http://localhost:8000/openapi.json..."
	@curl -s http://localhost:8000/openapi.json | NO_COLOR=1 PYTHON_COLORS=0 python3 -m json.tool --indent 2 > openapi.json
	@echo "✓ OpenAPI spec updated and formatted in openapi.json"
