.PHONY: api worker test gym-check sync-gyms sync-gyms-prod docker-build ecr-push pause resume

# `python -m uvicorn` (not the console script) survives stale .venv shebangs
# left over from the CustomYoutubeService -> VideoService rename.
api:
	poetry run python -m uvicorn src.api.main:app --host 0.0.0.0 --port 8002 --reload

# `python -m pytest` (not the `pytest` console script) survives stale .venv
# shebangs left over from the CustomYoutubeService -> VideoService rename.
test:
	poetry run python -m pytest tests/ -v

# The background worker: pops the oldest queued gym and runs its
# scrape -> funnel -> enrich -> scan -> feed-write pipeline under the global
# video-worker lock, one run at a time. Long-running loop (Ctrl-C / SIGTERM to
# stop). Requires DATABASE_URL, APIFY_TOKEN, and the model provider keys in .env.
# `python -m` (not a console script) survives stale .venv shebangs.
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

# The pool scrape + per-gym scan are no longer standalone scripts: they are the
# background `worker` (see the `worker` target above), which the FastApiBackend
# drives per gym via the video_worker_queue.

# --- Production (AWS App Runner) — see ../DEPLOYMENT.md ---------------------
ECR ?= 259645229668.dkr.ecr.us-east-1.amazonaws.com/combatden-videoservice
SERVICE_ARN ?= arn:aws:apprunner:us-east-1:259645229668:service/combatden-videoservice/e86bea56dcdd4b6d8f71af2fe61dbf4c

# Build the serving image (gyms/ + videos/ baked in; see Dockerfile).
docker-build:
	docker build -t combatden-videoservice:latest .

# Build + push to ECR + trigger an App Runner deploy (AutoDeployments are off).
ecr-push: docker-build
	aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 259645229668.dkr.ecr.us-east-1.amazonaws.com
	docker tag combatden-videoservice:latest $(ECR):latest
	docker push $(ECR):latest
	aws apprunner start-deployment --region us-east-1 --service-arn $(SERVICE_ARN) --query 'OperationId' --output text

# Demo on/off: pause stops compute billing between demos; resume (~1 min) before.
pause:
	aws apprunner pause-service --region us-east-1 --service-arn $(SERVICE_ARN) --query 'Service.Status' --output text

resume:
	aws apprunner resume-service --region us-east-1 --service-arn $(SERVICE_ARN) --query 'Service.Status' --output text
