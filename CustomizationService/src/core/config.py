"""Settings — runtime configuration from the environment / `.env`."""

from __future__ import annotations

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

    log_level: str = "DEBUG"


settings = Settings()
