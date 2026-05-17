"""Settings — runtime configuration from the environment / `.env`."""

from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Pipeline configuration. Env vars (or `.env`) override every default."""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Every text + image call goes to the proxy; provider keys live there.
    litellm_proxy_url: str = "http://localhost:4000"
    litellm_proxy_key: str = "TODO-set-proxy-virtual-key"  # set in .env

    # Smallest/cheapest Claude tier (Haiku 4.5) — dev cost control.
    text_model: str = "claude-haiku-4-5"
    # Flux via Black Forest Labs (hardcoded, not .env): Google image models
    # need a paid-tier project this key's project isn't on.
    image_model: str = "flux-dev"
    # BFL is called directly (litellm's BFL image path is broken upstream),
    # like PhotoRoom — not via the proxy.
    bfl_api_key: str = "TODO-set-bfl-api-key"  # set in .env (BFL_API_KEY)
    bfl_api_base: str = "https://api.bfl.ai"

    # Extra re-asks when complete_structured output misses schema/validate.
    llm_max_retries: int = 3

    # PhotoRoom is called directly, not via the proxy — the one key the app holds.
    photoroom_api_key: str = "TODO-set-photoroom-api-key"  # set in .env
    photoroom_api_url: str = "https://sdk.photoroom.com/v1/segment"

    # Gemini vision model that validates a cutout (size TBD).
    bg_validation_model: str = "gemini-2.5-flash"

    # Bounded remover re-calls; on exhaustion the un-removed image is kept.
    bg_max_attempts: int = 3

    log_level: str = "DEBUG"


settings = Settings()
