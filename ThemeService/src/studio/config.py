"""Studio settings — where runs, logs and briefs live, plus CORS."""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

# This file is <root>/src/studio/config.py; runs live in <root>/apps.
_ROOT = Path(__file__).resolve().parent.parent.parent
_DEFAULT_APPS_ROOT = _ROOT / "apps"

# The studio's own state lives OUTSIDE any run directory. A run's produced
# artifacts are never touched by anything but the pipeline (CLAUDE.md's
# iron-clad rule), so the run log cannot live beside output.yaml.
STUDIO_DIRNAME = ".studio"
RUNS_DIRNAME = "runs"
BRIEFS_DIRNAME = "briefs"
# One JSON object per line, append-only. See src/studio/schema/run_record.py.
RUN_LOG_SUFFIX = ".jsonl"
BRIEF_SUFFIX = ".yaml"

# The ThemeReact dev server. It is pinned to 8080 with `strictPort`
# (ThemeReact/vite.config.ts) because ../FastApiBackend's CORS allowlist has
# 8080 and not 5173 — so this list follows the React app, never the reverse.
# Both hostnames are listed because http://localhost:8080 and
# http://127.0.0.1:8080 are different browser origins.
_DEFAULT_CORS_ORIGINS = ["http://localhost:8080", "http://127.0.0.1:8080"]


class Settings(BaseSettings):
    """Studio config. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Root that holds `<app_id>/<run_id>/` — the same tree the read API
    # serves and the CLI writes.
    apps_root: Path = _DEFAULT_APPS_ROOT
    # The studio's own durable state (run logs + saved briefs). Gitignored.
    studio_root: Path = _ROOT / STUDIO_DIRNAME
    # Named apart from the read API's `cors_origins` so a shared `.env`
    # can't set one from the other: they front different audiences (the
    # emulator vs. one local browser tab).
    studio_cors_origins: list[str] = _DEFAULT_CORS_ORIGINS

    # --- The brief agent (src/studio/agent/) ------------------------------
    # A BARE Anthropic model name, never a litellm "provider/model" string:
    # the agent names its provider explicitly (`AnthropicProvider`), so the
    # id stands alone. Override with BRIEF_AGENT_MODEL.
    #
    # Its ANTHROPIC_API_KEY is deliberately NOT redeclared here — the studio
    # already imports the pipeline, so `src.core.config.settings` is the one
    # definition of that secret and `brief_agent_service()` reads it there.
    # A second copy would be a second requiredness rule for one env var.
    brief_agent_model: str = "claude-opus-5"
    # Extra re-asks when the agent's structured output misses the schema.
    brief_agent_retries: int = 3

    @property
    def runs_dir(self) -> Path:
        """Where one append-only `<run_id>.jsonl` per launch is written."""
        return self.studio_root / RUNS_DIRNAME

    @property
    def briefs_dir(self) -> Path:
        """Where a committed brand brief is saved as `<slug>.yaml`."""
        return self.studio_root / BRIEFS_DIRNAME


settings = Settings()
