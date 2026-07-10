# Combined FastApiBackend + VideoService-worker deployment image.
#
# Build context is the MONOREPO ROOT (not this directory), because the image
# needs three sibling directories: FastApiBackend/, VideoService/, and
# Database/python_data/schema/ (FastApiBackend imports it at runtime via a
# path shim — see FastApiBackend/src/shared/db_schema_path.py). Build with:
#
#   docker build -f deploy/Dockerfile -t combatden-backend-worker .
#
# Runs exactly TWO processes (see entrypoint.sh):
#   1. FastApiBackend       — uvicorn API on :8000
#   2. VideoService worker  — `python -m src.worker.run` (background job loop
#      that pops the video_worker_queue and runs each gym's scrape -> funnel ->
#      enrich -> scan -> feed-write pipeline; not a web server, no port)
#
# It deliberately does NOT run VideoService's read API (src/api, port 8002) —
# that stays on its own standalone App Runner service for the MobileApp until
# that client is repointed at FastApiBackend.
#
# Target platform is an always-on service (ECS Express Mode direction), not
# App Runner (CPU throttling on an idle/scale-to-zero platform would starve a
# background worker) — but nothing in this Dockerfile is platform-specific.
#
# Each app gets its OWN in-project poetry venv (POETRY_VIRTUALENVS_IN_PROJECT)
# instead of one shared environment: the two pyproject.toml files pin
# different fastapi/uvicorn ranges (FastApiBackend fastapi 0.135.x / uvicorn
# 0.42.x vs VideoService fastapi 0.136.x / uvicorn 0.47.x), so a single merged
# install risks a resolver conflict or a silent "wrong version wins" outcome.
# Two isolated venvs sidestep that entirely.

FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=true

# Poetry version pinned the same way as VideoService/Dockerfile.
RUN pip install "poetry>=2.0,<3.0"

WORKDIR /app

# --- FastApiBackend: dependency layer first, cached unless lock/pyproject change ---
COPY FastApiBackend/pyproject.toml FastApiBackend/poetry.lock /app/FastApiBackend/
RUN cd /app/FastApiBackend && poetry install --only main --no-root

# --- VideoService: same pattern, its own isolated venv ---
COPY VideoService/pyproject.toml VideoService/poetry.lock /app/VideoService/
RUN cd /app/VideoService && poetry install --only main --no-root

# --- Application source ---
COPY FastApiBackend/src/ /app/FastApiBackend/src/
COPY VideoService/src/ /app/VideoService/src/
COPY VideoService/schema/ /app/VideoService/schema/

# --- Database/python_data: the sibling package FastApiBackend path-shims onto
# sys.path (src/shared/db_schema_path.py resolves 4 parents up from itself and
# appends /Database/python_data), so it must land at /app/Database/python_data
# — a sibling of /app/FastApiBackend, mirroring the monorepo's own relative
# layout. Only `schema/` is imported at runtime (pure pydantic + stdlib, plus
# a couple of co-located .md waiver/disclosure bodies read via Path(__file__)
# — copying the whole directory keeps those alongside their .py readers).
# VideoService does not use this package (it has its own top-level `schema/`).
COPY Database/python_data/schema/ /app/Database/python_data/schema/

COPY deploy/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Only the FastApiBackend API is network-reachable from this image; the worker
# has no listening port.
EXPOSE 8000

ENTRYPOINT ["/entrypoint.sh"]
