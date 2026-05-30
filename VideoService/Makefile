.PHONY: api test gym-check scrape scan

# `python -m uvicorn` (not the console script) survives stale .venv shebangs
# left over from the CustomYoutubeService -> VideoService rename.
api:
	poetry run python -m uvicorn src.api.main:app --host 0.0.0.0 --port 8002 --reload

# `python -m pytest` (not the `pytest` console script) survives stale .venv
# shebangs left over from the CustomYoutubeService -> VideoService rename.
test:
	poetry run python -m pytest tests/ -v

# Validate a gym file round-trips the Gym model (schema + enum + filename match)
# before the scraper/scan touch it. The gym_maker job — authors/validates gyms,
# never scrapes or scans. Usage: make gym-check GYM_ID=vinyasa  (GYM_ID=all for all).
gym-check:
	poetry run python -m scripts.gym_maker.run check $(if $(filter all,$(GYM_ID)),--all,--gym-id $(GYM_ID))

# Scrape + classify the shared pool in one run: gather the gyms' queries, fetch
# from Apify (ONE actor does search + metadata + channel avatar + the transcript
# inline), REPLACE videos/, then tag each pooled video (genre + gym_type) — a
# gym-agnostic pass, no approval. Requires APIFY_TOKEN + the tagging model key
# (e.g. GEMINI_API_KEY) in .env. Appends SEARCH + TAG entries to cost_log.yaml.
# Usage: make scrape  (all gyms' queries)  |  make scrape GYM_ID=vinyasa (one gym).
scrape:
	poetry run python -m scripts.scraper.run $(if $(GYM_ID),--gym-id $(GYM_ID),)

# Scan the pool for one gym (or all) against the gym's own specification ->
# OVERWRITE that gym's good_video_ids / rejected_video_ids (its feed) and append a
# ScanCost to its history. Candidates are only the pool's videos tagged with the
# gym's discipline(s) (run `make scrape` first). Requires the model key (e.g.
# GEMINI_API_KEY) in .env. Appends a SCAN entry to cost_log.yaml.
# Usage: make scan GYM_ID=vinyasa   (or GYM_ID=all for every gym).
scan:
	poetry run python -m scripts.scan.run $(if $(filter all,$(GYM_ID)),--all-gyms,--gym-id $(GYM_ID))
