"""Provider-key wiring for Pydantic AI.

Pydantic AI resolves a model from a string like ``anthropic:claude-sonnet-4-6``
and reads that provider's API key from the environment. The backend keeps secrets
in ``Settings`` (never read by services directly), so the DI layer calls
``configure_provider_keys`` once — at agent/generator build time — to publish the
non-empty keys into the environment. ``setdefault`` so a real ambient env var
always wins and we never clobber it.

This is what keeps the agent **provider-swappable**: change the model *string* in
settings to repoint to any provider whose key is present here.
"""

from __future__ import annotations

import os

from pydantic_ai import Agent

from src.shared.database import DirectDatabasePool
from src.video_config.schema.video_config_schema import VideoConfigDraft
from src.video_config.service.video_config_agent import (
    VideoConfigAgentOutput,
    VideoConfigDeps,
    build_video_config_agent,
)
from src.video_config.service.video_config_feed_refiner import (
    VideoConfigFeedRefiner,
)
from src.video_config.service.video_config_query_generator import (
    VideoConfigQueryGenerator,
)

# model-string provider prefix -> the env var Pydantic AI reads for that provider.
_PROVIDER_ENV_VARS = {
    "anthropic_api_key": "ANTHROPIC_API_KEY",
    "openai_api_key": "OPENAI_API_KEY",
    "gemini_api_key": "GEMINI_API_KEY",
}


def configure_provider_keys(
    *,
    anthropic_api_key: str = "",
    openai_api_key: str = "",
    gemini_api_key: str = "",
) -> None:
    """Publish each non-empty provider key into the environment (setdefault)."""
    values = {
        "anthropic_api_key": anthropic_api_key,
        "openai_api_key": openai_api_key,
        "gemini_api_key": gemini_api_key,
    }
    for field, env_var in _PROVIDER_ENV_VARS.items():
        key = values[field]
        if key:
            os.environ.setdefault(env_var, key)


def build_query_generator(
    *,
    model: str,
    retries: int,
    anthropic_api_key: str = "",
    openai_api_key: str = "",
    gemini_api_key: str = "",
) -> VideoConfigQueryGenerator:
    """DI builder: publish provider keys, then build the query generator."""
    configure_provider_keys(
        anthropic_api_key=anthropic_api_key,
        openai_api_key=openai_api_key,
        gemini_api_key=gemini_api_key,
    )
    return VideoConfigQueryGenerator(model=model, retries=retries)


def build_config_agent(
    *,
    model: str,
    retries: int,
    anthropic_api_key: str = "",
    openai_api_key: str = "",
    gemini_api_key: str = "",
) -> Agent[VideoConfigDeps, VideoConfigAgentOutput]:
    """DI builder: publish provider keys, then build the conversational agent."""
    configure_provider_keys(
        anthropic_api_key=anthropic_api_key,
        openai_api_key=openai_api_key,
        gemini_api_key=gemini_api_key,
    )
    return build_video_config_agent(model=model, retries=retries)


def build_feed_refiner(
    *,
    model: str,
    retries: int,
    db_pool: DirectDatabasePool,
    anthropic_api_key: str = "",
    openai_api_key: str = "",
    gemini_api_key: str = "",
) -> VideoConfigFeedRefiner:
    """DI builder: publish provider keys, then build the feed-learning refiner."""
    configure_provider_keys(
        anthropic_api_key=anthropic_api_key,
        openai_api_key=openai_api_key,
        gemini_api_key=gemini_api_key,
    )
    agent: Agent[None, VideoConfigDraft] = Agent(
        model,
        output_type=VideoConfigDraft,
        retries=retries,
        # Resolve the model (and its provider key) at call time, not now, so the
        # backend boots even before ANTHROPIC_API_KEY is configured.
        defer_model_check=True,
    )
    return VideoConfigFeedRefiner(db_pool=db_pool, agent=agent)
