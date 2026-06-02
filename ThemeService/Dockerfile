# ThemeService — read-only theme catalog + asset API (AWS App Runner target).
#
# Serves the theme catalog + design detail (the per-run output.yaml) over a
# GET-only FastAPI. Image/icon BYTES are served from S3/CloudFront, NOT here, so
# the heavy apps/**/{images,final_images,icons}/ dirs are excluded via
# .dockerignore — `COPY apps/` brings only the small output.yaml metadata
# (~MB, not ~2.6 GB). The API defaults ASSETS_CDN_BASE_URL to the prod CDN, so
# it emits CDN URLs out of the box (no runtime env var needed).
# Pipeline-only material (assets/, scripts/, tests/) is also excluded.
#
# config.py resolves apps_root to <root>/apps and the package root is <root>/src,
# so with WORKDIR=/app everything lands at /app/* and paths resolve unchanged.
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

# Source packages (src/ incl. src/core + src/api/schema; top-level schema/) and
# the served assets. resources/ is tiny and copied as cheap insurance for any
# transitive read from src/core.
COPY src/ ./src/
COPY schema/ ./schema/
COPY resources/ ./resources/
COPY apps/ ./apps/

# Runtime env (App Runner service vars, never baked in):
#  - GOOGLE_FONTS_API_KEY (required) — the font-delivery endpoint hits Google's catalog.
#  - ASSETS_CDN_BASE_URL — OPTIONAL. Defaults to the prod CDN
#    (https://cdn.combatden.net) in code, so the API emits absolute CDN URLs
#    without it being set. Only set it to point at a different CDN, or set it
#    empty to serve relative/local paths (dev only — bytes aren't baked here).
#  - CORS_ORIGINS is optional (defaults to ["*"]).
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
