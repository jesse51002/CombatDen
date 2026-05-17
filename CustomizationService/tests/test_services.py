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
from src.shared.services.bfl_image_generator import BflImageGenerator
from src.shared.services.image_generator import ProxyImageGenerator
from src.shared.services.llm_client import ProxyLLMClient, _loggable


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
# ProxyLLMClient
# --------------------------------------------------------------------------


def test_complete_structured_returns_validated_model(monkeypatch):
    async def fake_acompletion(**kwargs):
        return _FakeCompletion(json.dumps({"x": 42}))

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)

    result = asyncio.run(
        ProxyLLMClient().complete_structured(
            [{"role": "user", "content": "give me x"}],
            schema=Tiny,
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
            ProxyLLMClient().complete_structured(
                [{"role": "user", "content": "give me x"}],
                schema=Tiny,
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
            ProxyLLMClient().complete(
                [{"role": "user", "content": "hi"}],
            )
        )


# --------------------------------------------------------------------------
# ProxyImageGenerator
# --------------------------------------------------------------------------


class _FakeImageItem:
    def __init__(self, b64_json: str) -> None:
        self.b64_json = b64_json


class _FakeImageResponse:
    def __init__(self, b64_json: str) -> None:
        self.data = [_FakeImageItem(b64_json)]


def test_image_generate_writes_file_and_returns_abspath(monkeypatch, tmp_path):
    payload = b"\x89PNG-fake-bytes"
    b64 = base64.b64encode(payload).decode()

    async def fake_aimage_generation(**kwargs):
        return _FakeImageResponse(b64)

    monkeypatch.setattr(litellm, "aimage_generation", fake_aimage_generation)

    dest = tmp_path / "nested" / "out.png"
    result = asyncio.run(ProxyImageGenerator().generate("a logo", dest))

    assert dest.read_bytes() == payload
    assert str(result).startswith("/")
    assert str(result) == str(dest.resolve())


def test_image_generate_error_maps_to_provider_error(monkeypatch, tmp_path):
    async def fake_aimage_generation(**kwargs):
        raise RuntimeError("image backend down")

    monkeypatch.setattr(litellm, "aimage_generation", fake_aimage_generation)

    with pytest.raises(ProviderError):
        asyncio.run(
            ProxyImageGenerator().generate("a logo", tmp_path / "x.png")
        )


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
# BflImageGenerator
# --------------------------------------------------------------------------


_BFL_POLL_URL = "https://poll.bfl.test/abc"
_BFL_SAMPLE_URL = "https://img.bfl.test/x.png"


class _FakeBflResponse:
    def __init__(self, *, json_body: dict | None = None, content: bytes = b""):
        self._json = json_body
        self.content = content

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict | None:
        return self._json


class _FakeBflClient:
    """httpx.AsyncClient stand-in: submit -> poll -> sample download."""

    poll_body: dict = {"status": "Ready", "result": {"sample": _BFL_SAMPLE_URL}}
    sample_bytes: bytes = b"\x89PNG-flux-bytes"

    def __init__(self, *args, **kwargs) -> None:
        pass

    async def __aenter__(self) -> "_FakeBflClient":
        return self

    async def __aexit__(self, *exc) -> None:
        return None

    async def post(self, *args, **kwargs) -> _FakeBflResponse:
        return _FakeBflResponse(json_body={"polling_url": _BFL_POLL_URL})

    async def get(self, url, *args, **kwargs) -> _FakeBflResponse:
        if url == _BFL_POLL_URL:
            return _FakeBflResponse(json_body=self.poll_body)
        return _FakeBflResponse(content=self.sample_bytes)


def test_bfl_generate_writes_file_and_returns_abspath(monkeypatch, tmp_path):
    monkeypatch.setattr(httpx, "AsyncClient", _FakeBflClient)

    dest = tmp_path / "nested" / "hero.png"
    result = asyncio.run(BflImageGenerator().generate("a hero", dest))

    assert dest.read_bytes() == _FakeBflClient.sample_bytes
    assert str(result) == str(dest.resolve())


def test_bfl_generate_failed_status_maps_to_provider_error(
    monkeypatch, tmp_path
):
    class FailClient(_FakeBflClient):
        poll_body = {"status": "Content Moderated"}

    monkeypatch.setattr(httpx, "AsyncClient", FailClient)

    with pytest.raises(ProviderError):
        asyncio.run(BflImageGenerator().generate("x", tmp_path / "x.png"))


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
