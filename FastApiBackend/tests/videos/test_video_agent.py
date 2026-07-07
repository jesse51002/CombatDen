"""Unit tests for the video spec / video agent — no DB, no real LLM key required.

Generator and refiner tests mock ``litellm.acompletion`` so no real provider
call is made. Agent tests use Pydantic AI's ``TestModel`` / ``FunctionModel``
via ``agent.override()``. No DB schema migration is required to run these.
"""

from __future__ import annotations

import json
from datetime import UTC, datetime
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch
from uuid import UUID, uuid4

import pytest
from pydantic import ValidationError
from pydantic_ai.messages import ModelMessagesTypeAdapter, ModelResponse, ToolCallPart
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel
from schema.video import GymVideoSpecSource

import src.shared.db_schema_path  # noqa: F401  — enables ``from schema.*`` imports
from src.shared.litellm_client import LiteLLMClient
from src.videos.schema.video_agent_schema import AgentTurnRequest, SpecProposal
from src.videos.schema.video_spec_schema import (
    MAX_GENERATED_QUERIES,
    MAX_LANDSCAPE_ITEMS,
    LandscapeResult,
    QueriesResult,
    VideoSpecDraft,
    VideoSpecView,
)
from src.videos.schema.videos_gym_type import GymType
from src.videos.service.video_agent.video_agent_service import VideoAgentService
from src.videos.service.video_feed_refiner import VideoFeedRefiner
from src.videos.service.video_query_generator import VideoQueryGenerator
from src.videos.service.video_spec_authoring import VideoSpecAuthoring
from src.videos.service.video_spec_service import VideoSpecService
from src.videos.service.videos_service import VideosService

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

GYM_ID: UUID = uuid4()

# The count VideoSpecAuthoring is constructed with in these tests (mirrors the
# settings.video_query_count DI injection).
_QUERY_COUNT = 30

# Criteria-only draft args — no 'queries' field (removed from VideoSpecDraft).
_DRAFT_ARGS: dict[str, Any] = {
    "disciplines": ["mma"],
    "videos_desc": "keep technique and fun",
    "avoid_desc": "no rage bait or scams",
    "short_videos_desc": None,
    "short_avoid_desc": None,
}

# The agent's proposal output bundles a chat message with the criteria draft.
_PROPOSAL_ARGS: dict[str, Any] = {
    "message": "Here's the spec I put together — review it and accept, or tell me what to change.",
    "draft": _DRAFT_ARGS,
}

_QUERIES_JSON = json.dumps({"queries": ["mma technique", "mma knockouts"]})

# Canned landscape-research output (call 1 of the two-call query generator).
_LANDSCAPE_JSON = json.dumps(
    {
        "channels": ["UFC (fight promotion)", "BJJ Fanatics (instructionals)"],
        "creators": ["Khabib Nurmagomedov", "Gordon Ryan"],
        "series_events": ["ADCC", "UFC 300"],
    }
)


def _emit_draft(messages: list, info: AgentInfo) -> ModelResponse:
    """FunctionModel handler: emit a SpecProposal (message + draft) via its tool."""
    tool = next(t for t in info.output_tools if "Proposal" in t.name)
    return ModelResponse(parts=[ToolCallPart(tool_name=tool.name, args=_PROPOSAL_ARGS)])


_QUESTION_ARGS: dict[str, Any] = {
    "question": "What is this gym's vibe?",
    "options": ["Hardcore fight team", "Welcoming and social", "Competition-driven"],
    "multi_select": False,
}


def _emit_question(messages: list, info: AgentInfo) -> ModelResponse:
    """FunctionModel handler: emit an AgentQuestion via its output tool."""
    tool = next(t for t in info.output_tools if "Question" in t.name)
    return ModelResponse(parts=[ToolCallPart(tool_name=tool.name, args=_QUESTION_ARGS)])


def _make_current_view() -> VideoSpecView:
    return VideoSpecView(
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


def _make_spec_service_stub() -> VideoSpecService:
    """Build a VideoSpecService whose db is a stub."""
    db_stub = MagicMock()
    return VideoSpecService(db_pool=db_stub)


def _make_litellm_client() -> LiteLLMClient:
    return LiteLLMClient(anthropic_api_key="test-key")


def _make_facade_stub() -> VideosService:
    """Build a minimal facade stub for agent tests.

    Only ``load_latest_spec`` and ``save_accepted_spec`` are needed now that
    the agent has no tools.
    """
    stub = MagicMock(spec=VideosService)
    stub.load_latest_spec = AsyncMock(return_value=None)
    stub.save_accepted_spec = AsyncMock(return_value=None)
    return stub


def _make_agent_service(videos_service: VideosService) -> VideoAgentService:
    """Build a VideoAgentService for testing (fake key, real construction)."""
    return VideoAgentService(
        videos_service=videos_service,
        model_name="claude-sonnet-4-6",
        retries=1,
        anthropic_api_key="test-key",
    )


def _mock_litellm_response(content: str) -> MagicMock:
    """Build a mock litellm response whose choices[0].message.content is ``content``."""
    resp = MagicMock()
    resp.choices[0].message.content = content
    return resp


def _acompletion_side_effect(*_args: Any, **kwargs: Any) -> MagicMock:
    """Two-call stub for ``litellm.acompletion``: return the LandscapeResult JSON
    for the landscape call and the QueriesResult JSON for the query call, keyed
    off the ``response_format`` schema so call order doesn't matter."""
    schema = kwargs["response_format"]
    content = _LANDSCAPE_JSON if schema is LandscapeResult else _QUERIES_JSON
    return _mock_litellm_response(content)


# ---------------------------------------------------------------------------
# 1. Query generator (litellm path)
# ---------------------------------------------------------------------------


async def test_query_generator_returns_expected_list() -> None:
    """Two-call flow mocked (landscape then queries): the query list is returned."""
    client = _make_litellm_client()
    gen = VideoQueryGenerator(
        litellm_client=client,
        model="anthropic/claude-sonnet-4-6",
    )
    mock_acompletion = AsyncMock(side_effect=_acompletion_side_effect)
    with patch("litellm.acompletion", mock_acompletion):
        result = await gen.generate(
            disciplines=[GymType.MMA],
            videos_desc="technique and fun",
            avoid_desc="no rage bait",
            count=5,
        )

    assert result == ["mma technique", "mma knockouts"]


async def test_query_generator_two_call_flow() -> None:
    """generate() runs landscape research then query gen: exactly two calls, and
    the landscape names + count land in the SECOND (query) prompt while the
    discipline text is in the FIRST (landscape) prompt."""
    client = _make_litellm_client()
    gen = VideoQueryGenerator(
        litellm_client=client,
        model="anthropic/claude-sonnet-4-6",
    )
    mock_acompletion = AsyncMock(side_effect=_acompletion_side_effect)
    with patch("litellm.acompletion", mock_acompletion):
        result = await gen.generate(
            disciplines=[GymType.MMA],
            videos_desc="technique and fun",
            avoid_desc="no rage bait",
            count=30,
        )

    assert result == ["mma technique", "mma knockouts"]
    assert mock_acompletion.call_count == 2

    first_prompt = mock_acompletion.call_args_list[0].kwargs["messages"][0]["content"]
    second_prompt = mock_acompletion.call_args_list[1].kwargs["messages"][0]["content"]

    # Call 1 is the landscape prompt (carries the discipline text).
    assert "mma" in first_prompt.lower()
    # Call 2 is the query prompt (carries the landscape names + the count).
    assert "Gordon Ryan" in second_prompt
    assert "UFC" in second_prompt
    assert "30" in second_prompt


# ---------------------------------------------------------------------------
# 2. Conversational agent — reply path (no tools, no deps)
# ---------------------------------------------------------------------------


async def test_agent_reply_path_returns_str() -> None:
    """TestModel(call_tools=[]) skips tool invocation; the agent emits plain text."""
    facade = _make_facade_stub()
    svc = _make_agent_service(facade)
    with svc._agent.override(model=TestModel(call_tools=[])):
        result = await svc._agent.run("hi")

    assert isinstance(result.output, str)
    assert result.output  # non-empty


# ---------------------------------------------------------------------------
# 3. Conversational agent — draft path
# ---------------------------------------------------------------------------


async def test_agent_draft_path_returns_spec_proposal() -> None:
    """FunctionModel emits a SpecProposal; output carries a message + the draft."""
    facade = _make_facade_stub()
    svc = _make_agent_service(facade)
    with svc._agent.override(model=FunctionModel(_emit_draft)):
        result = await svc._agent.run("confirm my config")

    assert isinstance(result.output, SpecProposal)
    assert result.output.message  # non-empty
    assert result.output.draft.disciplines == [GymType.MMA]


# ---------------------------------------------------------------------------
# 4. agent_turn — normal path (reply and draft)
# ---------------------------------------------------------------------------


async def test_agent_turn_reply_sets_reply_clears_draft() -> None:
    """agent_turn with TestModel: reply is a str, draft is None, history round-trips."""
    facade = _make_facade_stub()
    svc = _make_agent_service(facade)

    with svc._agent.override(model=TestModel(call_tools=[])):
        resp = await svc.agent_turn(GYM_ID, AgentTurnRequest(message="hi"))

    assert isinstance(resp.reply, str)
    assert resp.draft is None
    assert resp.saved is False
    assert len(resp.history) > 0
    # History must round-trip through the ModelMessages type adapter.
    ModelMessagesTypeAdapter.validate_python(resp.history)
    assert isinstance(resp.usage, dict)


async def test_agent_turn_proposal_sets_reply_and_draft() -> None:
    """agent_turn with a SpecProposal: reply (the message) AND draft are both set."""
    facade = _make_facade_stub()
    svc = _make_agent_service(facade)

    with svc._agent.override(model=FunctionModel(_emit_draft)):
        resp = await svc.agent_turn(
            GYM_ID, AgentTurnRequest(message="confirm my config")
        )

    assert isinstance(resp.reply, str)
    assert resp.reply  # the proposal's message accompanies the draft
    assert isinstance(resp.draft, VideoSpecDraft)
    assert resp.draft.disciplines == [GymType.MMA]
    assert resp.saved is False
    assert len(resp.history) > 0
    ModelMessagesTypeAdapter.validate_python(resp.history)
    assert isinstance(resp.usage, dict)


async def test_agent_turn_question_sets_question() -> None:
    """agent_turn with a FunctionModel emitting a multiple-choice question:
    question is set, reply + draft are None."""
    facade = _make_facade_stub()
    svc = _make_agent_service(facade)

    with svc._agent.override(model=FunctionModel(_emit_question)):
        resp = await svc.agent_turn(GYM_ID, AgentTurnRequest(message="hi"))

    assert resp.reply is None
    assert resp.draft is None
    assert resp.question is not None
    assert resp.question.question == "What is this gym's vibe?"
    assert len(resp.question.options) == 3
    assert resp.question.multi_select is False
    assert resp.saved is False
    ModelMessagesTypeAdapter.validate_python(resp.history)


# ---------------------------------------------------------------------------
# 5. agent_turn — accept-path (saved=True)
# ---------------------------------------------------------------------------


async def test_agent_turn_accept_path_saved() -> None:
    """When accepted_spec is provided and save succeeds, saved=True, draft=None."""
    facade = _make_facade_stub()
    saved_view = _make_current_view()
    facade.save_accepted_spec = AsyncMock(return_value=saved_view)
    svc = _make_agent_service(facade)

    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="keep technique and fun",
        avoid_desc="no rage bait",
    )

    with svc._agent.override(model=TestModel(call_tools=[])):
        resp = await svc.agent_turn(
            GYM_ID, AgentTurnRequest(accepted_spec=draft)
        )

    facade.save_accepted_spec.assert_called_once_with(GYM_ID, draft)
    assert resp.saved is True
    assert resp.draft is None
    assert isinstance(resp.reply, str)
    assert len(resp.history) > 0


async def test_agent_turn_accept_path_unchanged() -> None:
    """When accepted_spec matches current spec (diff guard), saved=True, view=None."""
    facade = _make_facade_stub()
    facade.save_accepted_spec = AsyncMock(return_value=None)  # diff guard: no change
    svc = _make_agent_service(facade)

    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="keep technique and fun",
        avoid_desc="no rage bait",
    )

    with svc._agent.override(model=TestModel(call_tools=[])):
        resp = await svc.agent_turn(
            GYM_ID, AgentTurnRequest(accepted_spec=draft)
        )

    assert resp.saved is True
    assert resp.draft is None
    assert isinstance(resp.reply, str)


async def test_agent_turn_accept_path_agent_fail_returns_fallback() -> None:
    """When save succeeds but the post-commit agent call raises, saved=True with fallback reply."""
    facade = _make_facade_stub()
    saved_view = _make_current_view()
    facade.save_accepted_spec = AsyncMock(return_value=saved_view)
    svc = _make_agent_service(facade)

    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="keep technique and fun",
        avoid_desc="no rage bait",
    )

    # Patch the internal agent.run to raise
    with svc._agent.override(model=TestModel(call_tools=[])):
        from unittest.mock import patch
        with patch.object(svc._agent, "run", side_effect=RuntimeError("LLM unavailable")):
            resp = await svc.agent_turn(
                GYM_ID, AgentTurnRequest(accepted_spec=draft, history=[])
            )

    facade.save_accepted_spec.assert_called_once()
    assert resp.saved is True
    assert isinstance(resp.reply, str)
    assert resp.draft is None
    assert resp.history == []
    assert resp.usage is None


async def test_agent_turn_accept_path_returns_draft() -> None:
    """When the post-save agent emits a SpecProposal, reply + draft are both set."""
    facade = _make_facade_stub()
    saved_view = _make_current_view()
    facade.save_accepted_spec = AsyncMock(return_value=saved_view)
    svc = _make_agent_service(facade)

    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="keep technique and fun",
        avoid_desc="no rage bait",
    )

    with svc._agent.override(model=FunctionModel(_emit_draft)):
        resp = await svc.agent_turn(
            GYM_ID, AgentTurnRequest(accepted_spec=draft)
        )

    assert resp.saved is True
    assert isinstance(resp.reply, str)
    assert resp.reply  # the proposal's message is non-empty
    assert isinstance(resp.draft, VideoSpecDraft)


async def test_agent_turn_accept_path_returns_question() -> None:
    """When the post-save agent emits an AgentQuestion, question is set (not reply)."""
    from src.videos.schema.video_agent_schema import AgentQuestion

    facade = _make_facade_stub()
    facade.save_accepted_spec = AsyncMock(return_value=_make_current_view())
    svc = _make_agent_service(facade)

    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="keep technique and fun",
        avoid_desc="no rage bait",
    )

    with svc._agent.override(model=FunctionModel(_emit_question)):
        resp = await svc.agent_turn(
            GYM_ID, AgentTurnRequest(accepted_spec=draft)
        )

    assert resp.saved is True
    assert isinstance(resp.question, AgentQuestion)
    assert resp.reply is None
    assert resp.draft is None


# ---------------------------------------------------------------------------
# 6. VideoSpecAuthoring.commit — diff guard
# ---------------------------------------------------------------------------


async def test_authoring_commit_no_change_returns_none() -> None:
    """When criteria are identical to the current spec, commit returns None."""
    spec_service = _make_spec_service_stub()
    query_gen = MagicMock(spec=VideoQueryGenerator)
    authoring = VideoSpecAuthoring(
        spec_service=spec_service,
        query_generator=query_gen,
        query_count=_QUERY_COUNT,
    )

    current = _make_current_view()
    spec_service.load_latest = AsyncMock(return_value=current)  # type: ignore[method-assign]

    # Draft with identical criteria to the current view
    draft = VideoSpecDraft(
        disciplines=[GymType(d) for d in current.disciplines],
        videos_desc=current.videos_desc,
        avoid_desc=current.avoid_desc,
        short_videos_desc=current.short_videos_desc,
        short_avoid_desc=current.short_avoid_desc,
    )

    result = await authoring.commit(
        GYM_ID, draft, source=GymVideoSpecSource.admin_update
    )

    assert result is None
    query_gen.generate.assert_not_called()


async def test_authoring_commit_changed_generates_and_saves() -> None:
    """When criteria differ from the current spec, commit generates and saves."""
    spec_service = _make_spec_service_stub()
    query_gen = MagicMock(spec=VideoQueryGenerator)
    query_gen.generate = AsyncMock(return_value=["query1", "query2"])
    authoring = VideoSpecAuthoring(
        spec_service=spec_service,
        query_generator=query_gen,
        query_count=_QUERY_COUNT,
    )

    current = _make_current_view()
    spec_service.load_latest = AsyncMock(return_value=current)  # type: ignore[method-assign]

    saved_view = _make_current_view()
    spec_service.save_version = AsyncMock(return_value=saved_view)  # type: ignore[method-assign]

    # Different videos_desc triggers the diff
    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="CHANGED keep criteria — this is different",
        avoid_desc=current.avoid_desc,
    )

    result = await authoring.commit(
        GYM_ID, draft, source=GymVideoSpecSource.admin_update
    )

    assert result is not None
    query_gen.generate.assert_called_once()
    spec_service.save_version.assert_called_once()


async def test_authoring_commit_discipline_reorder_triggers_change() -> None:
    """Reordering disciplines (primary changes) is a change, not a no-op."""
    spec_service = _make_spec_service_stub()
    query_gen = MagicMock(spec=VideoQueryGenerator)
    query_gen.generate = AsyncMock(return_value=["q1"])
    authoring = VideoSpecAuthoring(
        spec_service=spec_service,
        query_generator=query_gen,
        query_count=_QUERY_COUNT,
    )

    current = VideoSpecView(
        gym_id=GYM_ID,
        disciplines=["mma", "boxing"],  # mma is primary
        videos_desc="technique and fun",
        avoid_desc="no rage bait",
        queries=["q1"],
        source=GymVideoSpecSource.admin_update,
        imported_from=None,
        created_at=datetime.now(UTC),
    )
    spec_service.load_latest = AsyncMock(return_value=current)  # type: ignore[method-assign]
    spec_service.save_version = AsyncMock(return_value=current)  # type: ignore[method-assign]

    # Reversed order: boxing is now primary — this IS a change
    draft = VideoSpecDraft(
        disciplines=[GymType.BOXING, GymType.MMA],
        videos_desc=current.videos_desc,
        avoid_desc=current.avoid_desc,
    )

    result = await authoring.commit(
        GYM_ID, draft, source=GymVideoSpecSource.admin_update
    )

    assert result is not None
    query_gen.generate.assert_called_once()


async def test_authoring_commit_summary_only_reuses_queries() -> None:
    """A short_videos_desc / short_avoid_desc only change reuses queries (no LLM call)."""
    spec_service = _make_spec_service_stub()
    query_gen = MagicMock(spec=VideoQueryGenerator)
    query_gen.generate = AsyncMock(return_value=["new_q"])
    authoring = VideoSpecAuthoring(
        spec_service=spec_service,
        query_generator=query_gen,
        query_count=_QUERY_COUNT,
    )

    current = _make_current_view()  # short_videos_desc=None, short_avoid_desc=None
    spec_service.load_latest = AsyncMock(return_value=current)  # type: ignore[method-assign]
    spec_service.save_version = AsyncMock(return_value=current)  # type: ignore[method-assign]

    # Only the display summaries differ — query-affecting fields unchanged
    draft = VideoSpecDraft(
        disciplines=[GymType(d) for d in current.disciplines],
        videos_desc=current.videos_desc,
        avoid_desc=current.avoid_desc,
        short_videos_desc="New short summary",
        short_avoid_desc=None,
    )

    result = await authoring.commit(
        GYM_ID, draft, source=GymVideoSpecSource.admin_update
    )

    assert result is not None
    query_gen.generate.assert_not_called()
    # The existing queries are passed through to save_version
    call_args = spec_service.save_version.call_args
    assert call_args[0][2] == current.queries  # queries arg is the existing ones


async def test_authoring_commit_no_current_spec_always_saves() -> None:
    """When the gym has no spec yet, commit always saves (no diff possible)."""
    spec_service = _make_spec_service_stub()
    query_gen = MagicMock(spec=VideoQueryGenerator)
    query_gen.generate = AsyncMock(return_value=["q1"])
    authoring = VideoSpecAuthoring(
        spec_service=spec_service,
        query_generator=query_gen,
        query_count=_QUERY_COUNT,
    )

    spec_service.load_latest = AsyncMock(return_value=None)  # type: ignore[method-assign]
    saved_view = _make_current_view()
    spec_service.save_version = AsyncMock(return_value=saved_view)  # type: ignore[method-assign]

    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="brand new gym",
        avoid_desc="nothing bad",
    )

    result = await authoring.commit(
        GYM_ID, draft, source=GymVideoSpecSource.admin_update
    )

    assert result is not None
    query_gen.generate.assert_called_once()


async def test_authoring_commit_uses_settings_query_count(monkeypatch) -> None:
    """The injected query_count (settings.video_query_count) flows through commit
    into the generator's second (query) prompt."""
    from src.core.config import settings

    monkeypatch.setattr(settings, "video_query_count", 17)

    client = _make_litellm_client()
    gen = VideoQueryGenerator(
        litellm_client=client,
        model="anthropic/claude-sonnet-4-6",
    )
    spec_service = _make_spec_service_stub()
    # No current spec -> commit always generates (no diff short-circuit).
    spec_service.load_latest = AsyncMock(return_value=None)  # type: ignore[method-assign]
    spec_service.save_version = AsyncMock(  # type: ignore[method-assign]
        return_value=_make_current_view()
    )

    authoring = VideoSpecAuthoring(
        spec_service=spec_service,
        query_generator=gen,
        query_count=settings.video_query_count,
    )
    draft = VideoSpecDraft(
        disciplines=[GymType.MMA],
        videos_desc="brand new gym",
        avoid_desc="nothing bad",
    )

    mock_acompletion = AsyncMock(side_effect=_acompletion_side_effect)
    with patch("litellm.acompletion", mock_acompletion):
        result = await authoring.commit(
            GYM_ID, draft, source=GymVideoSpecSource.admin_update
        )

    assert result is not None
    assert mock_acompletion.call_count == 2
    second_prompt = mock_acompletion.call_args_list[1].kwargs["messages"][0]["content"]
    assert "17" in second_prompt


# ---------------------------------------------------------------------------
# 7. Feed refiner — no-signals branch + signal rendering
# ---------------------------------------------------------------------------


def _make_refiner() -> VideoFeedRefiner:
    """A VideoFeedRefiner with stub deps — only ``_render_signals`` is exercised
    here (it reads the signal-entry .md template in __init__)."""
    return VideoFeedRefiner(
        db_pool=MagicMock(),
        spec_service=_make_spec_service_stub(),
        litellm_client=_make_litellm_client(),
        model="anthropic/claude-sonnet-4-6",
        authoring=MagicMock(spec=VideoSpecAuthoring),
    )


def test_feed_refiner_render_signals_reject_with_reason() -> None:
    """_render_signals includes title, description, transcript, and curation_reason."""
    signals = [
        {
            "video_id": "abc123",
            "title": "Top 10 Brawls Compilation",
            "channel_name": "FightHub",
            "description": "Street brawls and bar fights caught on camera.",
            "transcript": "Welcome to today's brawl compilation.",
            "scan_status": "rejected",
            "curation_type": "manual",
            "curation_reason": "Too violent and unrelated to training",
        }
    ]
    rendered = _make_refiner()._render_signals(signals)
    assert "Top 10 Brawls Compilation" in rendered
    assert "rejected this video" in rendered
    assert "Reason given: Too violent and unrelated to training" in rendered
    assert "Description:" in rendered
    assert "Street brawls" in rendered
    assert "Transcript:" in rendered
    assert "brawl compilation" in rendered


def test_feed_refiner_render_signals_keep_with_accept_reason() -> None:
    """_render_signals uses curation_reason for kept signals."""
    signals = [
        {
            "video_id": "xyz789",
            "title": "BJJ Blue Belt Techniques",
            "channel_name": "GracieGarage",
            "description": "Fundamental BJJ techniques for beginners.",
            "transcript": "Today we cover the basics of guard passing.",
            "scan_status": "accepted",
            "curation_type": "manual",
            "curation_reason": "Great technique content for beginners",
        }
    ]
    rendered = _make_refiner()._render_signals(signals)
    assert "BJJ Blue Belt Techniques" in rendered
    assert "kept this video" in rendered
    assert "Reason given: Great technique content for beginners" in rendered
    assert "Description:" in rendered
    assert "Transcript:" in rendered


def test_feed_refiner_render_signals_no_reason_no_transcript() -> None:
    """_render_signals handles missing optional fields gracefully."""
    signals = [
        {
            "video_id": "nnn000",
            "title": "Boxing Highlights",
            "channel_name": "PunchTV",
            "description": None,
            "transcript": None,
            "scan_status": "rejected",
            "curation_type": "manual",
            "curation_reason": None,
        }
    ]
    rendered = _make_refiner()._render_signals(signals)
    assert "Boxing Highlights" in rendered
    assert "rejected this video" in rendered
    # Absent optional fields render as a graceful em-dash, not omitted.
    assert "Reason given: —" in rendered
    assert "Description: —" in rendered
    assert "Transcript: —" in rendered


async def test_feed_refiner_no_signals_returns_none() -> None:
    """When _load_signals returns [], refine_from_feed() returns None without calling the model."""
    db_stub = MagicMock()
    spec_service = _make_spec_service_stub()
    client = _make_litellm_client()
    authoring_stub = MagicMock(spec=VideoSpecAuthoring)
    refiner = VideoFeedRefiner(
        db_pool=db_stub,
        spec_service=spec_service,
        litellm_client=client,
        model="anthropic/claude-sonnet-4-6",
        authoring=authoring_stub,
    )

    current = _make_current_view()
    spec_service.load_latest = AsyncMock(return_value=current)  # type: ignore[method-assign]

    async def _no_signals(gym_id: UUID) -> list:
        return []

    with patch.object(refiner, "_load_signals", side_effect=_no_signals):
        result = await refiner.refine_from_feed(GYM_ID)

    assert result is None


# ---------------------------------------------------------------------------
# 8. VideoSpecDraft validation
# ---------------------------------------------------------------------------


def test_video_spec_draft_invalid_discipline_raises() -> None:
    """A discipline string outside the GymType enum fails validation."""
    with pytest.raises(ValidationError):
        VideoSpecDraft(
            disciplines=["definitely_not_a_real_gym_type"],
            videos_desc="some desc",
            avoid_desc="some avoid",
        )


def test_video_spec_draft_empty_disciplines_raises() -> None:
    """disciplines requires at least one item (min_length=1)."""
    with pytest.raises(ValidationError):
        VideoSpecDraft(
            disciplines=[],
            videos_desc="some desc",
            avoid_desc="some avoid",
        )


def test_video_spec_draft_valid_round_trips() -> None:
    """A valid draft serialises and deserialises cleanly (no queries field)."""
    draft = VideoSpecDraft(
        disciplines=[GymType.MMA, GymType.BOXING],
        videos_desc="technique tutorials and highlight reels",
        avoid_desc="no rage bait or scams",
        short_videos_desc="keep it technical",
        short_avoid_desc="nothing controversial",
    )
    reloaded = VideoSpecDraft.model_validate(draft.model_dump())
    assert reloaded.disciplines == [GymType.MMA, GymType.BOXING]
    assert reloaded.short_videos_desc == "keep it technical"
    assert reloaded.short_avoid_desc == "nothing controversial"
    # Confirm queries field is absent from VideoSpecDraft (no queries authored by agent)
    assert "queries" not in VideoSpecDraft.model_fields


def test_queries_result_truncates_runaway_lists() -> None:
    """LLM list outputs are hard-capped (cost guard): a runaway model gets
    truncated, never rejected (a reject would churn the structured-output
    retry loop while every extra query is real Apify spend)."""
    runaway = QueriesResult(
        queries=[f"query {i}" for i in range(MAX_GENERATED_QUERIES + 40)]
    )
    assert len(runaway.queries) == MAX_GENERATED_QUERIES
    assert runaway.queries[0] == "query 0"

    landscape = LandscapeResult(
        channels=[f"ch {i}" for i in range(MAX_LANDSCAPE_ITEMS + 10)],
        creators=["a"],
        series_events=[],
    )
    assert len(landscape.channels) == MAX_LANDSCAPE_ITEMS
    assert landscape.creators == ["a"]
