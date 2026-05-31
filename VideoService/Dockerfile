# VideoService — read-only, gym-id-keyed video feed API (AWS App Runner target).
#
# Serves gyms/<gym_id>.yaml + the shared videos/ pool (~300 MB) over a GET-only
# FastAPI. The video pool is NOT in git, so it is baked into the image here.
# Scraper/scan pipeline dirs (scripts/, tests/) are excluded via .dockerignore.
#
# config.py resolves data_root to <root> (it reads <root>/{gyms,videos}), and
# the package root is <root>/src, so with WORKDIR=/app everything resolves.
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

# Source packages (src/ incl. src/api; top-level schema/) and the served data.
# cost_log.yaml is small and copied so any audit/viewer read never hits a
# missing file; it is not exposed by the public feed endpoints.
COPY src/ ./src/
COPY schema/ ./schema/
COPY gyms/ ./gyms/
COPY videos/ ./videos/
COPY cost_log.yaml ./cost_log.yaml

# No secrets needed at serve time. CORS_ORIGINS optional (defaults to ["*"]).
# `python -m uvicorn` (not the console script) per the Makefile note about
# stale venv shebangs from the CustomYoutubeService -> VideoService rename.
EXPOSE 8002
CMD ["python", "-m", "uvicorn", "src.api.main:app", "--host", "0.0.0.0", "--port", "8002"]
