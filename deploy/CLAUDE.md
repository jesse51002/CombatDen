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
   background loop (no job queue) that derives the highest-priority due gym
   from timestamps already in the schema each tick and runs its scrape →
   funnel → enrich → scan → feed-write pipeline (not a web server, no exposed
   port).

Each app installs into its **own** poetry venv inside the image (different
fastapi/uvicorn version pins between the two projects), and the entrypoint
runs each process through its own venv's python.

## What does NOT run inside

**VideoService's read API** (`src/api`, port 8002) — that stays on its
existing standalone App Runner service serving the MobileApp, until that
client is repointed at FastApiBackend. This image only ships the worker.

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
FastApiBackend — read from `src/api/config.py`), `APIFY_TOKEN` (the scrape stage),
`GEMINI_API_KEY` (enrich + scan — default `gemini/gemini-2.5-flash-lite`), and
`OPENAI_API_KEY` (summary + query embeddings — default
`openai/text-embedding-3-small`). The provider keys resolve via VideoService's
`src/core/config.py`; the worker knobs (models, budgets, lock TTLs) live in
`src/worker/worker_config.py` with safe defaults. `ANTHROPIC_API_KEY` is accepted
but unused by the default worker models. See `VideoService/.env.example`.

## Platform note

Target is an **always-on service** (ECS Express Mode direction), **not App
Runner** — App Runner's CPU throttling on scale-to-idle would starve a
background worker process that needs to keep running between requests. The
Dockerfile itself is platform-agnostic; only the deployment target differs
from `ThemeService`/VideoService's read API (both still on App Runner — see
`../DEPLOYMENT.md`).

## Supervisor behavior (`entrypoint.sh`)

A short bash script starts both processes in the background, traps
SIGTERM/SIGINT to forward shutdown to both, and blocks on `wait -n` — the
first process to exit (crash OR normal exit) determines the container's exit
code. **If either process dies, the container exits nonzero and stops** rather
than silently continuing with only one process alive; the platform is
responsible for restarting it.
