# ThemeService — read-only theme catalog + asset API (AWS App Runner target).
#
# Serves apps/<app_id>/<run_id>/ (output.yaml + final_images/ + icons/) over a
# GET-only FastAPI. The 2.6 GB of `apps/` assets are NOT in git, so the image is
# the delivery vehicle — they are baked in here. Pipeline-only material
# (assets/, scripts/, tests/) is excluded via .dockerignore and never copied.
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

# GOOGLE_FONTS_API_KEY is required at runtime (the font-delivery endpoint hits
# Google's catalog). It is supplied as an App Runner env var, never baked in.
# CORS_ORIGINS is optional (defaults to ["*"]).
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8000"]
