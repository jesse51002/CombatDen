"""Settings — runtime configuration from the environment / `.env`."""

from __future__ import annotations

from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Pipeline configuration. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # litellm routes every call (text, vision, AND image generation) by
    # the provider prefix on that call's model id; the model id lives in
    # the module that makes the call (a per-call constant), never here.
    # These are the keys litellm uses for each provider.
    anthropic_api_key: str
    gemini_api_key: str
    openai_api_key: str

    # Extra re-asks when complete_structured output misses schema/validate.
    llm_max_retries: int = 3

    # PhotoRoom via its own httpx client (background removal).
    photoroom_api_key: str
    photoroom_api_url: str = "https://sdk.photoroom.com/v1/segment"

    # Recraft via its own httpx client (SVG icon generation for any icon
    # slot a curated set can't cover). Not litellm-routed — a direct
    # client, like PhotoRoom — so the key has no default (fail loud if
    # absent, matching every other provider key).
    recraft_api_key: str
    recraft_api_url: str = "https://external.api.recraft.ai/v1/images/generations"

    # Curated icon-set catalog: the directory holding one subdir per set
    # (<set_id>/set.yaml + icons/*.svg). Defaults to the repo-shipped
    # <CustomizationService>/assets/icon_sets/ (resolved relative to this
    # file so cwd doesn't matter); override to point at an alternate library.
    icon_sets_dir: Path = Path(__file__).resolve().parents[2] / "assets" / "icon_sets"

    # Google Fonts Developer API (https://developers.google.com/fonts/docs/developer_api).
    # Used by GoogleFontsCatalog to fetch + validate font families both at
    # pipeline-run time (font selection retry loop) and at API-serve time
    # (resolving the per-variant TTF URLs for the frontend). The key has
    # no default — fail loud if absent, matching every other provider key.
    google_fonts_api_key: str
    google_fonts_api_url: str = "https://www.googleapis.com/webfonts/v1/webfonts"
    # Generous: a one-shot list fetch for ~1700 families.
    google_fonts_request_timeout_seconds: float = 30.0
    # Catalog refresh interval. Google Fonts gains/removes families slowly,
    # so a 24h TTL is generous and cheap.
    google_fonts_ttl_seconds: int = 24 * 60 * 60

    log_level: str = "DEBUG"


settings = Settings()
