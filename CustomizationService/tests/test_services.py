"""Light, network-free tests for the three shared services."""

from __future__ import annotations

import asyncio
import base64
import json
from pathlib import Path

import httpx
import litellm
import pytest
from pydantic import BaseModel

from src.core.errors import ProviderError, SchemaValidationError
from src.shared.services.background_remover import PhotoRoomBackgroundRemover
from src.shared.services.litellm_image_generator import LiteLLMImageGenerator
from src.shared.services.llm_client import LiteLLMClient, _loggable
from src.shared.services.provider_keys import provider_api_key


# litellm.acompletion is monkeypatched in every test, but _completion_kwargs
# still resolves the provider key from this prefix, so it must be a
# configured provider ("anthropic"/"gemini").
_MODEL = "anthropic/claude-haiku-4-5-20251001"


class Tiny(BaseModel):
    """Throwaway schema for complete_structured tests."""

    x: int


class _FakeMessage:
    """Mimics a litellm choice message: model_dump() + ["content"]."""

    def __init__(self, content: str) -> None:
        self.content = content

    def model_dump(self) -> dict:
        return {"role": "assistant", "content": self.content}

    def __getitem__(self, key: str):
        if key == "content":
            return self.content
        raise KeyError(key)


class _FakeChoice:
    def __init__(self, content: str) -> None:
        self.message = _FakeMessage(content)


class _FakeCompletion:
    def __init__(self, content: str) -> None:
        self.choices = [_FakeChoice(content)]


# --------------------------------------------------------------------------
# LiteLLMClient
# --------------------------------------------------------------------------


def test_complete_structured_returns_validated_model(monkeypatch):
    async def fake_acompletion(**kwargs):
        return _FakeCompletion(json.dumps({"x": 42}))

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)

    result = asyncio.run(
        LiteLLMClient().complete_structured(
            [{"role": "user", "content": "give me x"}],
            schema=Tiny,
            model=_MODEL,
        )
    )
    assert isinstance(result, Tiny)
    assert result.x == 42


def test_complete_structured_raises_after_retries(monkeypatch):
    calls = {"n": 0}

    async def fake_acompletion(**kwargs):
        calls["n"] += 1
        return _FakeCompletion("not json at all")

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)

    with pytest.raises(SchemaValidationError):
        asyncio.run(
            LiteLLMClient().complete_structured(
                [{"role": "user", "content": "give me x"}],
                schema=Tiny,
                model=_MODEL,
            )
        )
    # llm_max_retries extra attempts + the first => total attempts.
    from src.core.config import settings

    assert calls["n"] == settings.llm_max_retries + 1


def test_complete_maps_litellm_error_to_provider_error(monkeypatch):
    async def fake_acompletion(**kwargs):
        raise RuntimeError("transport exploded")

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)

    with pytest.raises(ProviderError):
        asyncio.run(
            LiteLLMClient().complete(
                [{"role": "user", "content": "hi"}],
                model=_MODEL,
            )
        )


# --------------------------------------------------------------------------
# _loggable
# --------------------------------------------------------------------------


def test_loggable_elides_base64_image_but_keeps_text():
    encoded = "A" * 5000
    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": "is this cutout clean?"},
                {
                    "type": "image_url",
                    "image_url": {"url": f"data:image/png;base64,{encoded}"},
                },
            ],
        }
    ]

    flat = json.dumps(_loggable(messages))

    # Prompt text survives; the base64 blob is gone, replaced by a marker.
    assert "is this cutout clean?" in flat
    assert encoded not in flat
    assert "chars elided>" in flat
    # Deep copy — the real messages are untouched.
    assert messages[0]["content"][1]["image_url"]["url"].endswith(encoded)


# --------------------------------------------------------------------------
# provider_api_key
# --------------------------------------------------------------------------


def test_provider_api_key_routes_by_prefix():
    from src.core.config import settings

    assert (
        provider_api_key("openai/gpt-image-2") == settings.openai_api_key
    )
    assert (
        provider_api_key("anthropic/claude-opus-4-7")
        == settings.anthropic_api_key
    )


def test_provider_api_key_unknown_provider_raises():
    with pytest.raises(ProviderError):
        provider_api_key("nope/some-model")


# --------------------------------------------------------------------------
# LiteLLMImageGenerator
# --------------------------------------------------------------------------


class _FakeImageDatum:
    def __init__(self, b64_json: str) -> None:
        self.b64_json = b64_json


class _FakeImageResponse:
    def __init__(self, b64_json: str) -> None:
        self.data = [_FakeImageDatum(b64_json)]


def test_litellm_image_gen_writes_file_and_forwards_model_and_quality(
    monkeypatch, tmp_path
):
    png_bytes = b"\x89PNG-gpt-image-bytes"
    seen: dict = {}

    async def fake_aimage_generation(**kwargs):
        seen.update(kwargs)
        return _FakeImageResponse(base64.b64encode(png_bytes).decode())

    monkeypatch.setattr(litellm, "aimage_generation", fake_aimage_generation)

    dest = tmp_path / "nested" / "hero.png"
    result = asyncio.run(
        LiteLLMImageGenerator().generate(
            "a hero", dest, model="openai/gpt-image-2", quality="low"
        )
    )

    assert dest.read_bytes() == png_bytes
    assert str(result) == str(dest.resolve())
    # The per-call model + quality are forwarded to litellm verbatim.
    assert seen["model"] == "openai/gpt-image-2"
    assert seen["quality"] == "low"
    assert seen["prompt"] == "a hero"
    # Generation goes to a model that accepts ``n`` — it is still sent.
    assert seen["n"] == 1


def test_litellm_image_gen_maps_failure_to_provider_error(
    monkeypatch, tmp_path
):
    async def boom(**kwargs):
        raise RuntimeError("image API exploded")

    monkeypatch.setattr(litellm, "aimage_generation", boom)

    with pytest.raises(ProviderError):
        asyncio.run(
            LiteLLMImageGenerator().generate(
                "x", tmp_path / "x.png", model="openai/gpt-image-2",
                quality="medium",
            )
        )


# --------------------------------------------------------------------------
# PhotoRoomBackgroundRemover
# --------------------------------------------------------------------------


class _FakeHTTPResponse:
    def __init__(self, content: bytes, raises: bool) -> None:
        self.content = content
        self._raises = raises

    def raise_for_status(self) -> None:
        if self._raises:
            raise httpx.HTTPStatusError(
                "402", request=None, response=None
            )


class _FakeAsyncClient:
    """Stands in for httpx.AsyncClient as an async context manager."""

    _content = b"PNG"
    _raises = False

    def __init__(self, *args, **kwargs) -> None:
        pass

    async def __aenter__(self) -> "_FakeAsyncClient":
        return self

    async def __aexit__(self, *exc) -> None:
        return None

    async def post(self, *args, **kwargs) -> _FakeHTTPResponse:
        return _FakeHTTPResponse(self._content, self._raises)


def test_photoroom_remove_writes_dst(monkeypatch, tmp_path):
    src = tmp_path / "in.png"
    src.write_bytes(b"solid-bg-image")
    dst = tmp_path / "cut" / "out.png"

    class OkClient(_FakeAsyncClient):
        _content = b"transparent-png"
        _raises = False

    monkeypatch.setattr(httpx, "AsyncClient", OkClient)

    asyncio.run(PhotoRoomBackgroundRemover().remove(src, dst))
    assert dst.read_bytes() == b"transparent-png"


def test_photoroom_remove_error_maps_to_provider_error(
    monkeypatch, tmp_path
):
    src = tmp_path / "in.png"
    src.write_bytes(b"solid-bg-image")
    dst = tmp_path / "out.png"

    class FailClient(_FakeAsyncClient):
        _raises = True

    monkeypatch.setattr(httpx, "AsyncClient", FailClient)

    with pytest.raises(ProviderError):
        asyncio.run(PhotoRoomBackgroundRemover().remove(src, dst))
