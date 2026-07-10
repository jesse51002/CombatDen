# deploy/ — combined backend + video-worker deployment image

This directory holds the **one Docker image** that runs both `FastApiBackend`
(the API monolith) and `VideoService`'s background worker process together.
It does not build or run anything on its own — `FastApiBackend/` and
`VideoService/` remain the source of truth for their own code and dev
workflows (their own Makefiles, CLAUDE.md files, tests). This is packaging
only.

## Build

Build context is the **monorepo root**, not this directory (the image needs
`FastApiBackend/`, `VideoService/`, and `Database/python_data/schema/` as
siblings — see the Dockerfile header comment):

```
docker build -f deploy/Dockerfile -t combatden-backend-worker .
```

## What runs inside (exactly 2 processes, see `entrypoint.sh`)

1. **FastApiBackend** — `uvicorn src.main:app` on `:8000` (the CRM-facing API).
2. **VideoService worker** — `python -m src.worker.run`, a self-scheduling
   background loop (no job queue) that derives its work from timestamps already
   in the schema each tick and runs DECOUPLED DB-backed steps — cleanup +
   finalize (always), then ONE drained heavy step (scan, else enrich, else the
   quota-bound scrape). Only scrape is per-gym + run-opening; enrich and scan are
   global gym-agnostic sweeps that build the RAG layer and settle feed verdicts
   (not a web server, no exposed port).

Each app installs into its **own** poetry venv inside the image (different
fastapi/uvicorn version pins between the two projects), and the entrypoint
runs each process through its own venv's python.

## The former VideoService read API (merged into FastApiBackend, runs inside)

The old standalone **VideoService read API** (`VideoService/src/api`, port 8002)
that served the MobileApp's video content has been **removed** — it was
re-authored and merged into **FastApiBackend's `src/videos` domain**
(`GET /api/v1/gyms/{gym_id}/videos` for the paginated served feed, plus the
per-member `.../video-rec` + `.../video-rec/{rec_id}/click` endpoints). That
domain is served by the FastApiBackend uvicorn process **inside this image** on
`:8000`, so the MobileApp's video reads now come from FastApiBackend like the
CRM's do — there is no separate VideoService read service or port 8002 anymore.
This image ships that read API (as part of FastApiBackend) **and** the worker.

## Runtime environment variables

None are baked into the image — all secrets/config are injected by the
platform at container start. The authoritative list is each app's
`src/core/config.py` `Settings` class (`.env.example` in each app documents a
subset; config.py is more current). Names only, no values:

**FastApiBackend** (required — no default): `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `STRIPE_SECRET_KEY`,
`STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET`,
`STRIPE_CONNECT_REFRESH_URL`, `STRIPE_CONNECT_RETURN_URL`, `DATABASE_URL`,
`YOUTUBE_API_KEY`.

**FastApiBackend** (optional — safe defaults, set to enable/tune):
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY` (video-spec LLM
calls), `VIDEO_LLM_MODEL`, `VIDEO_AGENT_MODEL`, `APP_ENV`, `CORS_ORIGINS`,
plus a long tail of tuning knobs (reconciler cadence, lock TTLs, invoice-fetch
retries, etc.) — see `Settings` for the full set.

**VideoService worker** (`src/worker/`): `DATABASE_URL` (same shared Postgres as
FastApiBackend — read from `src/shared/config.py`), `APIFY_TOKEN` (the enrich
stage's lazy batched transcript fetch), and `GEMINI_API_KEY` (enrich + scan +
embed — enrich/scan default `gemini/gemini-2.5-flash-lite`, embeddings default
`gemini/gemini-embedding-001` → `vector(3072)`). The provider keys resolve via
VideoService's `src/core/config.py`; the worker knobs (models, budgets, lock
TTLs) live in `src/worker/worker_config.py` with safe defaults. `OPENAI_API_KEY`
and `ANTHROPIC_API_KEY` are accepted but unused by the default worker models
(all default to Gemini). See `VideoService/.env.example`.

## Platform note

Target is an **always-on service** (ECS Express Mode direction), **not App
Runner** — App Runner's CPU throttling on scale-to-idle would starve a
background worker process that needs to keep running between requests. The
Dockerfile itself is platform-agnostic; only the deployment target differs
from `ThemeService` (still on App Runner — see `../DEPLOYMENT.md`).
VideoService's former standalone read API is gone (merged into FastApiBackend,
above), so it is no longer a separate App Runner service.

## Supervisor behavior (`entrypoint.sh`)

A short bash script starts both processes in the background, traps
SIGTERM/SIGINT to forward shutdown to both, and blocks on `wait -n` — the
first process to exit (crash OR normal exit) determines the container's exit
code. **If either process dies, the container exits nonzero and stops** rather
than silently continuing with only one process alive; the platform is
responsible for restarting it.
