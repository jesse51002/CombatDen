.PHONY: worker test gym-check sync-gyms sync-gyms-prod enrich-templates

# `python -m pytest` (not the `pytest` console script) survives stale .venv
# shebangs left over from the CustomYoutubeService -> VideoService rename.
test:
	poetry run python -m pytest tests/ -v

# The background worker: self-schedules (no queue) the highest-priority due gym
# each tick and runs its scrape -> funnel -> enrich -> scan -> feed-write pipeline
# under the global video-worker lock, one run at a time. Long-running loop (Ctrl-C
# / SIGTERM to stop). Requires DATABASE_URL, YOUTUBE_API_KEY (scrape), APIFY_TOKEN
# (transcripts), and the model provider keys in .env. `python -m` (not a console
# script) survives stale .venv shebangs.
worker:
	poetry run python -m src.worker.run

# Validate a gym file round-trips the Gym model (schema + enum + filename match)
# before the scraper/scan touch it. The gym_maker job — authors/validates gyms,
# never scrapes or scans. Usage: make gym-check GYM_ID=vinyasa  (GYM_ID=all for all).
gym-check:
	poetry run python -m scripts.gym_maker.run check $(if $(filter all,$(GYM_ID)),--all,--gym-id $(GYM_ID))

# Sync the authored gym YAML files into SQL (video_gym + query/class/reward
# tables), then load the existing videos/ pool + each gym's good/rejected feeds
# into SQL (pool upserts, feeds rewrite per gym — both idempotent, no re-scrape).
# The append-only cost_log is intentionally NOT imported here (--skip-cost-log)
# so re-running never duplicates ledger rows; import it once by hand if needed:
#   poetry run python -m scripts.import_yaml.run
# Run after the migration creates the video_* tables.
# Usage: make sync-gyms GYM_ID=vinyasa  (GYM_ID=all for every gym).
# Targets the local DB (.env) by default; ENV_FILE=.env.prod targets prod, e.g.
#   ENV_FILE=.env.prod make sync-gyms GYM_ID=all
sync-gyms:
	poetry run python -m scripts.sync_gyms.run $(if $(filter all,$(GYM_ID)),--all,--gym-id $(GYM_ID))
	poetry run python -m scripts.import_yaml.run --skip-cost-log

# --- Prod (.env.prod) — same as above but against the prod DB ---------------
# Needs a .env.prod with the prod DATABASE_URL (gitignored). The host is logged
# before any write so you can confirm you're hitting prod. ENV_FILE propagates
# through the sync-gyms call, so this runs the sync + import against prod.
# Usage: make sync-gyms-prod GYM_ID=all
sync-gyms-prod:
	ENV_FILE=.env.prod $(MAKE) --no-print-directory sync-gyms GYM_ID=$(GYM_ID)

# One-time PAID run: enrich every unique template video (~18.9k, both feed
# verdicts) into the RAG sidecar (video_rag/video_rag.jsonl) so `make sync-gyms`
# can seed video_rag on any DB without re-paying the LLM. Reuses the worker
# enricher's per-video unit; resumable/idempotent (skips videos already in the
# sidecar), so a crashed run just re-runs. Run AFTER `make sync-gyms` (needs the
# pool + video_gym_feed loaded). Requires the keys the configured enrich_model +
# embedding_model use (by default GEMINI_API_KEY + OPENAI_API_KEY) and
# APIFY_TOKEN (lazy transcript fetches for the ~16% of videos with none) in .env.
# Targets the DB in ENV_FILE (default .env). Cost ~ $30-150 for the summary pass.
#   make enrich-templates
enrich-templates:
	poetry run python -m scripts.enrich_templates.run $(ARGS)
# Smoke-test the whole enrich->embed->sidecar pipeline on ONE video before the
# full paid run:  make enrich-templates ARGS="--limit 1 --root /tmp/enrich_smoke"

# The pool scrape + per-gym scan are no longer standalone scripts: they are the
# background `worker` (see the `worker` target above), which self-schedules the
# next due gym each tick from timestamps in the schema (no queue, no backend
# trigger).
