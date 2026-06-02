# VideoService — read-only, gym-id-keyed video feed API (AWS App Runner target).
#
# Serves gyms / videos / classes / rewards over a GET-only FastAPI, reading the
# shared Supabase Postgres (the video_* tables). NO data is baked into the image
# anymore — the pool lives in the DB — so the image is small (just src/ + deps).
# The scrape / scan / sync / import scripts run OUTSIDE this image.
#
# Requires DATABASE_URL at runtime (set on the App Runner service env), e.g.
#   postgresql+asyncpg://...  (a raw postgresql:// Supabase URL is also accepted —
#   it's normalised to asyncpg by src/shared/database.py). CORS_ORIGINS optional.
FROM python:3.13-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    POETRY_VIRTUALENVS_CREATE=false \
    POETRY_NO_INTERACTION=1

WORKDIR /app

# Dependency layer first — cached across rebuilds unless pyproject/lock change.
RUN pip install "poetry>=2.0,<3.0"
COPY pyproject.toml poetry.lock ./
RUN poetry install --only main --no-root

# Source only — the read path queries the DB, so no gyms/ / videos/ / cost_log.
COPY src/ ./src/
COPY schema/ ./schema/

# `python -m uvicorn` (not the console script) per the Makefile note about stale
# venv shebangs from the CustomYoutubeService -> VideoService rename.
EXPOSE 8002
CMD ["python", "-m", "uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8002"]
