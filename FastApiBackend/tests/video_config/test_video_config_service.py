"""Unit tests for the video_config domain — no DB, no real LLM key required.

All agent calls use Pydantic AI's TestModel (synthetic output) or FunctionModel
(fully controlled response shape). No DB schema migration is required to run
these: every path that would touch the database is either monkeypatched or
exercised via a path that doesn't reach the DB at all.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any
from unittest.mock import patch
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError
from pydantic_ai import Agent
from pydantic_ai.messages import ModelMessagesTypeAdapter, ModelResponse, ToolCallPart
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel
from schema.video import GymVideoSpecSource

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.video_config.schema.video_config_schema import (
    VideoConfigAgentRequest,
    VideoConfigDraft,
    VideoConfigView,
)
from src.video_config.service.video_config_agent import (
    VideoConfigDeps,
    build_video_config_agent,
)
from src.video_config.service.video_config_feed_refiner import VideoConfigFeedRefiner
from src.video_config.service.video_config_query_generator import (
    VideoConfigQueryGenerator,
)
from src.video_config.service.video_config_service import VideoConfigService
from src.videos.schema.videos_gym_type import GymType

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

GYM_ID: UUID = uuid4()

_DRAFT_ARGS: dict[str, Any] = {
    "disciplines": ["mma"],
    "videos_desc": "keep technique and fun",
    "avoid_desc": "no rage bait or scams",
    "short_videos_desc": None,
    "short_avoid_desc": None,
    "queries": ["mma technique", "mma knockouts"],
}

_QUERIES_ARGS: dict[str, Any] = {
    "queries": ["mma technique", "mma knockouts"],
}


def _emit_draft(messages: list, info: AgentInfo) -> ModelResponse:
    """FunctionModel handler: emit a VideoConfigDraft via the output tool."""
    name = info.output_tools[0].name
    return ModelResponse(parts=[ToolCallPart(tool_name=name, args=_DRAFT_ARGS)])


def _emit_queries(messages: list, info: AgentInfo) -> ModelResponse:
    """FunctionModel handler: emit a QueriesResult via the output tool."""
    name = info.output_tools[0].name
    return ModelResponse(parts=[ToolCallPart(tool_name=name, args=_QUERIES_ARGS)])


async def _load_nothing(gym_id: UUID) -> VideoConfigView | None:
    """Stub config-loader that simulates a gym with no config yet."""
    return None


def _make_current_view() -> VideoConfigView:
    return VideoConfigView(
        gym_id=GYM_ID,
        disciplines=["mma"],
        videos_desc="technique and fun",
        avoid_desc="no rage bait",
        short_videos_desc=None,
        short_avoid_desc=None,
        queries=["mma knockouts", "mma technique"],
        source=GymVideoSpecSource.admin_update,
        imported_from=None,
        created_at=datetime.now(UTC),
    )


def _make_service(
    agent: Agent,
    gen: VideoConfigQueryGenerator,
) -> VideoConfigService:
    """Build a VideoConfigService whose db-facing pieces are stubs."""
    from unittest.mock import MagicMock

    db_stub = MagicMock()
    refiner_agent: Agent = Agent(
        "anthropic:claude-sonnet-4-6",
        output_type=VideoConfigDraft,
        retries=1,
        defer_model_check=True,
    )
    refiner = VideoConfigFeedRefiner(db_pool=db_stub, agent=refiner_agent)
    return VideoConfigService(
        db_pool=db_stub,
        agent=agent,
        query_generator=gen,
        feed_refiner=refiner,
    )


# ---------------------------------------------------------------------------
# 1. Query generator
# ---------------------------------------------------------------------------


async def test_query_generator_returns_expected_list() -> None:
    """FunctionModel drives the query generator; the list of queries is returned."""
    gen = VideoConfigQueryGenerator(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    with gen._agent.override(model=FunctionModel(_emit_queries)):
        result = await gen.generate(
            disciplines=[GymType.MMA],
            videos_desc="technique and fun",
            avoid_desc="no rage bait",
            count=5,
        )

    assert result == ["mma technique", "mma knockouts"]


# ---------------------------------------------------------------------------
# 2. Conversational agent — reply path
# ---------------------------------------------------------------------------


async def test_agent_reply_path_returns_str() -> None:
    """TestModel(call_tools=[]) skips tool invocation; the agent emits plain text."""
    agent = build_video_config_agent(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    gen = VideoConfigQueryGenerator(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    deps = VideoConfigDeps(
        gym_id=GYM_ID,
        query_generator=gen,
        load_current_config=_load_nothing,
    )
    with agent.override(model=TestModel(call_tools=[])):
        result = await agent.run("hi", deps=deps)

    assert isinstance(result.output, str)
    assert result.output  # non-empty


# ---------------------------------------------------------------------------
# 3. Conversational agent — draft path
# ---------------------------------------------------------------------------


async def test_agent_draft_path_returns_video_config_draft() -> None:
    """FunctionModel emits a VideoConfigDraft; the agent output is the draft."""
    agent = build_video_config_agent(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    gen = VideoConfigQueryGenerator(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    deps = VideoConfigDeps(
        gym_id=GYM_ID,
        query_generator=gen,
        load_current_config=_load_nothing,
    )
    with agent.override(model=FunctionModel(_emit_draft)):
        result = await agent.run("confirm my config", deps=deps)

    assert isinstance(result.output, VideoConfigDraft)
    assert result.output.disciplines == [GymType.MMA]
    assert result.output.queries == ["mma technique", "mma knockouts"]


# ---------------------------------------------------------------------------
# 4. agent_turn mapping through VideoConfigService
# ---------------------------------------------------------------------------


async def test_agent_turn_reply_sets_reply_clears_draft() -> None:
    """agent_turn with TestModel: reply is a str, draft is None, history round-trips."""
    agent = build_video_config_agent(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    gen = VideoConfigQueryGenerator(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    svc = _make_service(agent, gen)

    with agent.override(model=TestModel(call_tools=[])):
        resp = await svc.agent_turn(GYM_ID, VideoConfigAgentRequest(message="hi"))

    assert isinstance(resp.reply, str)
    assert resp.draft is None
    assert len(resp.history) > 0
    # History must round-trip through the ModelMessages type adapter.
    ModelMessagesTypeAdapter.validate_python(resp.history)
    assert isinstance(resp.usage, dict)


async def test_agent_turn_draft_sets_draft_clears_reply() -> None:
    """agent_turn with FunctionModel: draft is set, reply is None, history round-trips."""
    agent = build_video_config_agent(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    gen = VideoConfigQueryGenerator(
        model="anthropic:claude-sonnet-4-6", retries=1
    )
    svc = _make_service(agent, gen)

    with agent.override(model=FunctionModel(_emit_draft)):
        resp = await svc.agent_turn(
            GYM_ID, VideoConfigAgentRequest(message="confirm my config")
        )

    assert resp.reply is None
    assert isinstance(resp.draft, VideoConfigDraft)
    assert resp.draft.disciplines == [GymType.MMA]
    assert len(resp.history) > 0
    ModelMessagesTypeAdapter.validate_python(resp.history)
    assert isinstance(resp.usage, dict)


# ---------------------------------------------------------------------------
# 5. Feed refiner — no-signals branch
# ---------------------------------------------------------------------------


async def test_feed_refiner_no_signals_returns_none() -> None:
    """When _load_signals returns [], propose() returns None without calling the model."""
    from unittest.mock import MagicMock

    db_stub = MagicMock()
    refiner_agent: Agent = Agent(
        "anthropic:claude-sonnet-4-6",
        output_type=VideoConfigDraft,
        retries=1,
        defer_model_check=True,
    )
    refiner = VideoConfigFeedRefiner(db_pool=db_stub, agent=refiner_agent)
    current = _make_current_view()

    async def _no_signals(gym_id: UUID) -> list:
        return []

    with patch.object(refiner, "_load_signals", side_effect=_no_signals):
        result = await refiner.propose(GYM_ID, current=current)

    assert result is None


# ---------------------------------------------------------------------------
# 6. VideoConfigDraft validation
# ---------------------------------------------------------------------------


def test_video_config_draft_invalid_discipline_raises() -> None:
    """A discipline string outside the GymType enum fails validation."""
    with pytest.raises(ValidationError):
        VideoConfigDraft(
            disciplines=["definitely_not_a_real_gym_type"],
            videos_desc="some desc",
            avoid_desc="some avoid",
        )


def test_video_config_draft_empty_disciplines_raises() -> None:
    """disciplines requires at least one item (min_length=1)."""
    with pytest.raises(ValidationError):
        VideoConfigDraft(
            disciplines=[],
            videos_desc="some desc",
            avoid_desc="some avoid",
        )


def test_video_config_draft_valid_round_trips() -> None:
    """A valid draft serialises and deserialises cleanly."""
    draft = VideoConfigDraft(
        disciplines=[GymType.MMA, GymType.BOXING],
        videos_desc="technique tutorials and highlight reels",
        avoid_desc="no rage bait or scams",
        short_videos_desc="keep it technical",
        short_avoid_desc="nothing controversial",
        queries=["mma knockouts", "boxing footwork"],
    )
    reloaded = VideoConfigDraft.model_validate(draft.model_dump())
    assert reloaded.disciplines == [GymType.MMA, GymType.BOXING]
    assert reloaded.queries == ["mma knockouts", "boxing footwork"]
    assert reloaded.short_videos_desc == "keep it technical"
