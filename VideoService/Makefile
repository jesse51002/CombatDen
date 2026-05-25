.PHONY: api test youtube classify smoke

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
youtube:
	poetry run python -m scripts.youtube_batch.run --app-id $(APP_ID)

# Classify a company's fetched videos -> rewrite videos_output.yaml with one
# content-derived tag + an is_good verdict per video. Reads videos_output.yaml
# (run `make youtube` first) and GEMINI_API_KEY in .env. No YouTube quota cost.
# Usage: make classify APP_ID=combatden
classify:
	poetry run python -m scripts.classify.run --app-id $(APP_ID)

# Smoke test: the real batch script against the one-search apps/smoketest brief.
# The cheapest real run (~100 quota units). Requires YOUTUBE_API_KEY in .env.
smoke:
	poetry run python -m scripts.youtube_batch.run --app-id smoketest
