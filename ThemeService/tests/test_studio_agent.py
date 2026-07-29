"""Brief-agent tests — no API key, no network, no provider call ever.

Every test overrides the agent's model with Pydantic AI's ``TestModel`` (plain
replies) or ``FunctionModel`` (a hand-built response aimed at one output tool
by name), so the real ``AnthropicModel`` is constructed but never called.
``BriefAgentService`` is otherwise built exactly as production builds it, with
a fake key, so the construction path is under test too.

Briefs land in a per-test temp dir; nothing here writes into ``apps/`` or the
real ``.studio/``.
"""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest
import yaml
from fastapi.testclient import TestClient
from pydantic_ai.messages import (
    ModelMessagesTypeAdapter,
    ModelResponse,
    ToolCallPart,
)
from pydantic_ai.models.function import AgentInfo, FunctionModel
from pydantic_ai.models.test import TestModel

from schema import Customization
from src.studio.agent import brief_agent_service as agent_module
from src.studio.agent.brief_agent_service import (
    SAVED_FALLBACK_REPLY,
    SYSTEM_PROMPT_PATH,
    BriefAgentService,
)
from src.studio.main import app
from src.studio.schema.agent_output import AgentQuestion
from src.studio.schema.agent_turn import AgentTurnRequest
from src.studio.service.brief_service import BriefService

# The five-field contract, nested exactly as `Customization` declares it.
_BRIEF: dict[str, Any] = {
    "design_direction": {
        "name": "Iron & Ash",
        "short_desc": "Heavy, warm, unfussy.",
        "long_desc": "A soot-and-ember gym brand: warm metal, hard edges.",
    },
    "colors_direction": {
        "description": "charcoal base with an ember orange accent",
        "mode": "dark",
    },
}

_PROPOSAL_ARGS: dict[str, Any] = {
    "message": "Here's the brief I put together — review it and accept, or "
    "tell me what to change.",
    "brief": _BRIEF,
}

_QUESTION_ARGS: dict[str, Any] = {
    "question": "What is this gym's personality?",
    "options": ["Hardcore fight team", "Welcoming and social", "Quietly premium"],
    "multi_select": False,
}


def _emit_proposal(messages: list[Any], info: AgentInfo) -> ModelResponse:
    """FunctionModel handler: emit a BriefProposal via its output tool."""
    tool = next(t for t in info.output_tools if "Proposal" in t.name)
    return ModelResponse(parts=[ToolCallPart(tool_name=tool.name, args=_PROPOSAL_ARGS)])


def _emit_question(messages: list[Any], info: AgentInfo) -> ModelResponse:
    """FunctionModel handler: emit an AgentQuestion via its output tool."""
    tool = next(t for t in info.output_tools if "Question" in t.name)
    return ModelResponse(parts=[ToolCallPart(tool_name=tool.name, args=_QUESTION_ARGS)])


def _service(briefs_dir: Path, key: str = "test-key") -> BriefAgentService:
    """A production-shaped service over a temp briefs dir and a fake key."""
    return BriefAgentService(
        briefs=BriefService(briefs_dir),
        model_name="claude-opus-5",
        retries=1,
        anthropic_api_key=key,
    )


@pytest.fixture
def svc(tmp_path: Path) -> BriefAgentService:
    return _service(tmp_path / "briefs")


@pytest.fixture
def client(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    """The real studio app with the agent singleton pointed at a temp dir.

    Yields ``(TestClient, service, briefs_dir)``; override the service's model
    around each request.
    """
    briefs_dir = tmp_path / "briefs"
    service = _service(briefs_dir)
    monkeypatch.setattr(agent_module, "_service", service)
    with TestClient(app) as test_client:
        yield test_client, service, briefs_dir


# --- construction ----------------------------------------------------------


def test_the_agent_is_built_with_no_tools(svc: BriefAgentService) -> None:
    """The agent converses and proposes; it never writes anything itself.

    "Agent authors, code commits" is the whole design — a tool here would be
    a second way to write a brief, bypassing ``BriefService.commit``.
    """
    assert svc._agent is not None
    assert not svc._agent._function_toolset.tools
    # And its instructions really are the .md, not an inlined string.
    assert SYSTEM_PROMPT_PATH.is_file()
    assert "five fields, never a sixth" in SYSTEM_PROMPT_PATH.read_text(
        encoding="utf-8"
    )


def test_an_empty_key_leaves_the_agent_unbuilt(tmp_path: Path) -> None:
    """Fail soft: no key means no agent, not a broken studio."""
    service = _service(tmp_path / "briefs", key="")
    assert service._agent is None
    with pytest.raises(LookupError, match="ANTHROPIC_API_KEY"):
        asyncio.run(service.turn(AgentTurnRequest(message="hi")))


def test_the_studio_still_boots_and_commits_without_a_key(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Only the agent endpoint fails; the plain form path is untouched."""
    monkeypatch.setattr(agent_module, "_service", _service(tmp_path / "b", key=""))
    with TestClient(app) as test_client:
        assert test_client.get("/health").json() == {"status": "ok"}
        resp = test_client.post("/brief-agent", json={"message": "hi"})
    assert resp.status_code == 503
    assert "ANTHROPIC_API_KEY" in resp.json()["detail"]


# --- the three output arms -------------------------------------------------


def test_turn_reply_sets_reply_only(svc: BriefAgentService) -> None:
    """TestModel(call_tools=[]) skips the output tools; the agent emits text."""
    with svc._agent.override(model=TestModel(call_tools=[])):
        resp = asyncio.run(svc.turn(AgentTurnRequest(message="hi")))

    assert isinstance(resp.reply, str) and resp.reply
    assert resp.draft is None
    assert resp.question is None
    assert resp.saved is False
    assert resp.committed is None
    # The transcript must round-trip through the adapter that produced it.
    ModelMessagesTypeAdapter.validate_python(resp.history)
    assert isinstance(resp.usage, dict)


def test_turn_proposal_sets_reply_and_draft(svc: BriefAgentService) -> None:
    """A proposal is never silent: the chat message rides with the brief."""
    with svc._agent.override(model=FunctionModel(_emit_proposal)):
        resp = asyncio.run(svc.turn(AgentTurnRequest(message="that's it")))

    assert isinstance(resp.reply, str) and resp.reply
    assert isinstance(resp.draft, Customization)
    assert resp.draft.design_direction.name == "Iron & Ash"
    assert resp.draft.colors_direction.mode.value == "dark"
    assert resp.question is None
    assert resp.saved is False
    ModelMessagesTypeAdapter.validate_python(resp.history)


def test_turn_question_sets_question_only(svc: BriefAgentService) -> None:
    with svc._agent.override(model=FunctionModel(_emit_question)):
        resp = asyncio.run(svc.turn(AgentTurnRequest(message="hi")))

    assert resp.reply is None
    assert resp.draft is None
    assert resp.question is not None
    assert resp.question.question == _QUESTION_ARGS["question"]
    assert len(resp.question.options) == 3
    assert resp.question.multi_select is False


def test_a_proposal_can_only_carry_the_five_fields() -> None:
    """extra='forbid' rides all the way down: no sixth field is expressible."""
    with pytest.raises(ValueError, match="vibe"):
        Customization.model_validate({**_BRIEF, "vibe": "spicy"})


def test_a_question_needs_two_to_six_options() -> None:
    with pytest.raises(ValueError):
        AgentQuestion(question="?", options=["only one"])
    with pytest.raises(ValueError):
        AgentQuestion(question="?", options=[f"opt {i}" for i in range(7)])


# --- the accept path -------------------------------------------------------


def test_accept_commits_the_brief_then_acknowledges(
    svc: BriefAgentService, tmp_path: Path
) -> None:
    """The deterministic commit runs FIRST; the agent only acknowledges."""
    accepted = Customization.model_validate(_BRIEF)

    with svc._agent.override(model=TestModel(call_tools=[])):
        resp = asyncio.run(svc.turn(AgentTurnRequest(accepted_brief=accepted)))

    assert resp.saved is True
    assert resp.draft is None
    assert isinstance(resp.reply, str) and resp.reply
    assert resp.committed is not None
    assert resp.committed.slug == "iron-ash"

    written = tmp_path / "briefs" / "iron-ash.yaml"
    assert written.is_file()
    # Exactly the five-field contract on disk — the same bytes the form path
    # would have written.
    assert yaml.safe_load(written.read_text()) == _BRIEF


def test_accept_takes_an_explicit_slug(
    svc: BriefAgentService, tmp_path: Path
) -> None:
    accepted = Customization.model_validate(_BRIEF)
    with svc._agent.override(model=TestModel(call_tools=[])):
        resp = asyncio.run(
            svc.turn(AgentTurnRequest(accepted_brief=accepted, slug="my-draft"))
        )
    assert resp.committed is not None
    assert resp.committed.slug == "my-draft"
    assert (tmp_path / "briefs" / "my-draft.yaml").is_file()


def test_accept_surfaces_a_post_save_proposal(svc: BriefAgentService) -> None:
    """A post-save proposal is mapped, not flattened to reply-only."""
    accepted = Customization.model_validate(_BRIEF)
    with svc._agent.override(model=FunctionModel(_emit_proposal)):
        resp = asyncio.run(svc.turn(AgentTurnRequest(accepted_brief=accepted)))

    assert resp.saved is True
    assert isinstance(resp.reply, str) and resp.reply
    assert isinstance(resp.draft, Customization)


def test_accept_surfaces_a_post_save_question(svc: BriefAgentService) -> None:
    accepted = Customization.model_validate(_BRIEF)
    with svc._agent.override(model=FunctionModel(_emit_question)):
        resp = asyncio.run(svc.turn(AgentTurnRequest(accepted_brief=accepted)))

    assert resp.saved is True
    assert isinstance(resp.question, AgentQuestion)
    assert resp.reply is None
    assert resp.draft is None


def test_accept_degrades_when_the_post_save_call_fails(
    svc: BriefAgentService, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """The save already happened; a dead model must not undo that report."""
    accepted = Customization.model_validate(_BRIEF)

    async def _boom(*_args: Any, **_kwargs: Any) -> None:
        raise RuntimeError("provider unavailable")

    with svc._agent.override(model=TestModel(call_tools=[])):
        monkeypatch.setattr(svc._agent, "run", _boom)
        resp = asyncio.run(
            svc.turn(AgentTurnRequest(accepted_brief=accepted, history=[]))
        )

    assert resp.saved is True
    assert resp.reply == SAVED_FALLBACK_REPLY
    assert resp.draft is None
    assert resp.history == []
    assert resp.usage is None
    assert resp.committed is not None
    # The point of the degrade: the file is really there.
    assert (tmp_path / "briefs" / "iron-ash.yaml").is_file()


def test_accept_refuses_an_unsluggable_name(
    svc: BriefAgentService, tmp_path: Path
) -> None:
    """A commit failure is a real failure — nothing written, nothing claimed."""
    accepted = Customization.model_validate(
        {**_BRIEF, "design_direction": {**_BRIEF["design_direction"], "name": "!!!"}}
    )
    with svc._agent.override(model=TestModel(call_tools=[])):
        with pytest.raises(ValueError, match="slug"):
            asyncio.run(svc.turn(AgentTurnRequest(accepted_brief=accepted)))
    assert not (tmp_path / "briefs").exists()


# --- the request contract --------------------------------------------------


def test_a_blank_message_mid_conversation_is_refused() -> None:
    """Only the opening turn may omit the message."""
    with pytest.raises(ValueError, match="message"):
        AgentTurnRequest(message="   ", history=[{"kind": "request"}])


def test_a_blank_opening_message_is_fine(svc: BriefAgentService) -> None:
    """The browser opens the interview with an empty message."""
    with svc._agent.override(model=TestModel(call_tools=[])):
        resp = asyncio.run(svc.turn(AgentTurnRequest()))
    assert isinstance(resp.reply, str) and resp.reply


# --- the endpoint ----------------------------------------------------------


def test_endpoint_returns_a_reply_and_a_transcript(client) -> None:
    test_client, service, _ = client
    with service._agent.override(model=TestModel(call_tools=[])):
        resp = test_client.post("/brief-agent", json={"message": "hi"})

    assert resp.status_code == 200
    body = resp.json()
    assert isinstance(body["reply"], str) and body["reply"]
    assert body["draft"] is None
    assert body["question"] is None
    assert body["saved"] is False
    assert body["committed"] is None
    assert body["history"]


def test_endpoint_returns_a_proposal(client) -> None:
    test_client, service, _ = client
    with service._agent.override(model=FunctionModel(_emit_proposal)):
        resp = test_client.post("/brief-agent", json={"message": "done"})

    assert resp.status_code == 200
    body = resp.json()
    assert body["reply"]
    assert body["draft"] == _BRIEF
    assert body["saved"] is False


def test_endpoint_accept_writes_the_brief(client) -> None:
    test_client, service, briefs_dir = client
    with service._agent.override(model=TestModel(call_tools=[])):
        resp = test_client.post(
            "/brief-agent", json={"accepted_brief": _BRIEF, "history": []}
        )

    assert resp.status_code == 200
    body = resp.json()
    assert body["saved"] is True
    assert body["committed"]["slug"] == "iron-ash"
    assert body["committed"]["brief"] == _BRIEF
    assert yaml.safe_load((briefs_dir / "iron-ash.yaml").read_text()) == _BRIEF


def test_endpoint_rejects_a_sixth_brief_field(client) -> None:
    """No sixth field survives the wire either."""
    test_client, service, briefs_dir = client
    bad = {**_BRIEF, "vibe": "spicy"}
    with service._agent.override(model=TestModel(call_tools=[])):
        resp = test_client.post("/brief-agent", json={"accepted_brief": bad})
    assert resp.status_code == 422
    assert not briefs_dir.exists()


def test_endpoint_rejects_an_unsluggable_accepted_name(client) -> None:
    test_client, service, briefs_dir = client
    bad = {**_BRIEF, "design_direction": {**_BRIEF["design_direction"], "name": "!!!"}}
    with service._agent.override(model=TestModel(call_tools=[])):
        resp = test_client.post("/brief-agent", json={"accepted_brief": bad})
    assert resp.status_code == 422
    assert "slug" in resp.json()["detail"]
    assert not briefs_dir.exists()


def test_endpoint_rejects_an_unknown_request_field(client) -> None:
    test_client, service, _ = client
    with service._agent.override(model=TestModel(call_tools=[])):
        resp = test_client.post(
            "/brief-agent", json={"message": "hi", "session_id": "nope"}
        )
    assert resp.status_code == 422


def test_endpoint_500s_when_the_agent_raises(
    client, monkeypatch: pytest.MonkeyPatch
) -> None:
    test_client, service, _ = client

    async def _boom(*_args: Any, **_kwargs: Any) -> None:
        raise RuntimeError("provider unavailable")

    with service._agent.override(model=TestModel(call_tools=[])):
        monkeypatch.setattr(service._agent, "run", _boom)
        resp = test_client.post("/brief-agent", json={"message": "hi"})

    assert resp.status_code == 500
    assert resp.json()["detail"] == "The brief agent failed to respond."


def test_a_transcript_round_trips_across_two_turns(client) -> None:
    """The stateless contract: hand the history back and keep going."""
    test_client, service, _ = client
    with service._agent.override(model=TestModel(call_tools=[])):
        first = test_client.post("/brief-agent", json={"message": "hi"}).json()
        second = test_client.post(
            "/brief-agent",
            json={"message": "a fight gym", "history": first["history"]},
        ).json()

    assert len(second["history"]) > len(first["history"])
    ModelMessagesTypeAdapter.validate_python(second["history"])
