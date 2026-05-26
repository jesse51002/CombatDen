.PHONY: api test youtube transcripts classify smoke preview reset

# `python -m uvicorn` (not the console script) survives stale .venv shebangs
# left over from the CustomYoutubeService -> VideoService rename.
api:
	poetry run python -m uvicorn src.api.main:app --host 0.0.0.0 --port 8002 --reload

# `python -m pytest` (not the `pytest` console script) survives stale .venv
# shebangs left over from the CustomYoutubeService -> VideoService rename.
test:
	poetry run python -m pytest tests/ -v

# Run a company's searches against the YouTube Data API -> videos_output.yaml.
# Requires YOUTUBE_API_KEY in .env. Usage: make youtube APP_ID=combatden
# (regenerates apps/<id>/preview.html afterward).
youtube:
	poetry run python -m scripts.youtube_batch.run --app-id $(APP_ID)
	poetry run python -m scripts.preview --app-id $(APP_ID)

# Fetch transcripts for a company's fetched videos -> cache the full transcript
# on each per-video file. Reads the batch result (run `make youtube` first) and
# APIFY_TOKEN in .env. Costs ~$0.0005/transcript; only fetches videos that lack
# one, so re-runs are cheap. Usage: make transcripts APP_ID=combatden
# (regenerates apps/<id>/preview.html afterward).
transcripts:
	poetry run python -m scripts.transcripts.run --app-id $(APP_ID)
	poetry run python -m scripts.preview --app-id $(APP_ID)

# Classify a company's fetched videos -> rewrite each per-video file with one
# content-derived tag + an is_good verdict. Reads the batch result (run `make
# youtube` first; `make transcripts` first for best accuracy) and GEMINI_API_KEY
# in .env. No YouTube quota cost. Usage: make classify APP_ID=combatden
# (regenerates apps/<id>/preview.html afterward).
classify:
	poetry run python -m scripts.classify.run --app-id $(APP_ID)
	poetry run python -m scripts.preview --app-id $(APP_ID)

# Smoke test: the real batch script against the one-search apps/smoketest brief.
# The cheapest real run (~100 quota units). Requires YOUTUBE_API_KEY in .env.
smoke:
	poetry run python -m scripts.youtube_batch.run --app-id smoketest
	poetry run python -m scripts.preview --app-id smoketest

# Build a static HTML grid of a company's feed (thumbnail + verdict + transcript
# snippet) at apps/<app_id>/preview.html for eyeballing what was kept vs rejected.
# No deps, no server. Usage: make preview APP_ID=bjj  (omit APP_ID for every app).
preview:
	poetry run python -m scripts.preview $(if $(APP_ID),--app-id $(APP_ID),)

# Clear tag/is_good/reason on a company's videos (keeping transcripts) so the
# classifier can be re-run clean. Dev/test helper — spends nothing. Regenerates
# the preview. Usage: make reset APP_ID=bjj  (omit APP_ID to reset every app).
reset:
	poetry run python -m scripts.reset_classifications $(if $(APP_ID),--app-id $(APP_ID),)
	poetry run python -m scripts.preview $(if $(APP_ID),--app-id $(APP_ID),)
