"""LiteLLMClient upgrades for the video worker — pure, no network/DB.

Stubs ``litellm.acompletion`` / ``litellm.aembedding`` / ``litellm.completion_cost``
via monkeypatch and asserts:

- multimodal: ``image_urls`` rebuilds the last user message into litellm's
  multi-part ``[text, image_url...]`` shape (and the no-image path is untouched);
- ``complete_structured_with_cost`` RETURNS the cost and never stashes it on the
  shared instance;
- ``embed`` request shape (model / input / provider-resolved api_key), input-order
  vectors, returned cost, and ProviderError wrapping.

Follows the suite's ``asyncio.run`` convention (no pytest-asyncio).
"""

from __future__ import annotations

import asyncio

import litellm
import pytest
from pydantic import BaseModel

from src.core.errors import ProviderError
from src.shared.services.llm_client import LiteLLMClient


class _Verdict(BaseModel):
    ok: bool


class _FakeMessage:
    """A litellm message stand-in: supports ``["content"]`` and ``model_dump``."""

    def __init__(self, content: str) -> None:
        self._content = content

    def __getitem__(self, key: str) -> str:
        if key == "content":
            return self._content
        raise KeyError(key)

    def model_dump(self) -> dict:
        return {"role": "assistant", "content": self._content}


class _FakeChoice:
    def __init__(self, content: str) -> None:
        self.message = _FakeMessage(content)


class _FakeResp:
    def __init__(self, content: str) -> None:
        self.choices = [_FakeChoice(content)]


class _FakeEmb:
    def __init__(self, data: list) -> None:
        self.data = data


def _patch_completion(monkeypatch, captured: dict) -> None:
    async def fake_acompletion(**kwargs):
        captured.update(kwargs)
        return _FakeResp('{"ok": true}')

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)
    monkeypatch.setattr(litellm, "completion_cost", lambda **kw: 0.0)


def test_complete_structured_attaches_images_as_multipart(monkeypatch) -> None:
    captured: dict = {}
    _patch_completion(monkeypatch, captured)
    client = LiteLLMClient()

    result = asyncio.run(
        client.complete_structured(
            [{"role": "user", "content": "describe these"}],
            schema=_Verdict,
            model="anthropic/claude-x",
            image_urls=["https://img/a.jpg", "https://img/b.jpg"],
        )
    )

    assert result == _Verdict(ok=True)
    assert captured["response_format"] is _Verdict
    assert captured["messages"][-1]["content"] == [
        {"type": "text", "text": "describe these"},
        {"type": "image_url", "image_url": {"url": "https://img/a.jpg"}},
        {"type": "image_url", "image_url": {"url": "https://img/b.jpg"}},
    ]


def test_complete_structured_without_images_keeps_plain_content(
    monkeypatch,
) -> None:
    captured: dict = {}
    _patch_completion(monkeypatch, captured)
    client = LiteLLMClient()

    asyncio.run(
        client.complete_structured(
            [{"role": "user", "content": "hi"}],
            schema=_Verdict,
            model="anthropic/claude-x",
        )
    )

    assert captured["messages"][-1]["content"] == "hi"


def test_complete_structured_does_not_mutate_caller_messages(
    monkeypatch,
) -> None:
    captured: dict = {}
    _patch_completion(monkeypatch, captured)
    client = LiteLLMClient()
    messages = [{"role": "user", "content": "hi"}]

    asyncio.run(
        client.complete_structured(
            messages,
            schema=_Verdict,
            model="anthropic/claude-x",
            image_urls=["https://img/a.jpg"],
        )
    )

    # The caller's list/dict is untouched — the multipart rebuild is on a copy.
    assert messages == [{"role": "user", "content": "hi"}]


def test_images_without_user_message_raises(monkeypatch) -> None:
    _patch_completion(monkeypatch, {})
    client = LiteLLMClient()

    with pytest.raises(ValueError):
        asyncio.run(
            client.complete_structured(
                [{"role": "system", "content": "sys"}],
                schema=_Verdict,
                model="anthropic/claude-x",
                image_urls=["https://img/a.jpg"],
            )
        )


def test_with_cost_returns_cost_and_never_stashes(monkeypatch) -> None:
    async def fake_acompletion(**kwargs):
        return _FakeResp('{"ok": true}')

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)
    monkeypatch.setattr(litellm, "completion_cost", lambda **kw: 0.0025)
    client = LiteLLMClient()

    parsed, cost = asyncio.run(
        client.complete_structured_with_cost(
            [{"role": "user", "content": "hi"}],
            schema=_Verdict,
            model="anthropic/claude-x",
        )
    )

    assert parsed == _Verdict(ok=True)
    assert cost == 0.0025
    # The shared-instance running total stays untouched (concurrency-safe).
    assert client.cost == 0.0


def test_embed_request_shape_key_resolution_and_cost(monkeypatch) -> None:
    from src.core.config import settings as core_settings

    monkeypatch.setattr(core_settings, "openai_api_key", "sk-embed-test")
    captured: dict = {}

    async def fake_aembedding(**kwargs):
        captured.update(kwargs)
        # Deliberately out of input order to prove index-sorting.
        return _FakeEmb(
            [
                {"index": 1, "embedding": [0.3, 0.4]},
                {"index": 0, "embedding": [0.1, 0.2]},
            ]
        )

    monkeypatch.setattr(litellm, "aembedding", fake_aembedding)
    monkeypatch.setattr(litellm, "completion_cost", lambda **kw: 0.00042)
    client = LiteLLMClient()

    vectors, cost = asyncio.run(
        client.embed(
            ["first", "second"], model="openai/text-embedding-3-small"
        )
    )

    assert captured["model"] == "openai/text-embedding-3-small"
    assert captured["input"] == ["first", "second"]
    # Key resolved from the "openai/" provider prefix, same as completions.
    assert captured["api_key"] == "sk-embed-test"
    # Vectors returned in input order (by embedding index).
    assert vectors == [[0.1, 0.2], [0.3, 0.4]]
    assert cost == 0.00042
    assert client.cost == 0.0


def test_embed_wraps_provider_failure(monkeypatch) -> None:
    async def boom(**kwargs):
        raise RuntimeError("upstream down")

    monkeypatch.setattr(litellm, "aembedding", boom)
    client = LiteLLMClient()

    with pytest.raises(ProviderError):
        asyncio.run(
            client.embed(["x"], model="openai/text-embedding-3-small")
        )
