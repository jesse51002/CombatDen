"""Unit tests for ``LiteLLMClient`` — no real provider calls.

``litellm.aembedding`` is monkeypatched so no network request is made; the tests
assert the request shape (model / input / provider key) and that the returned
vectors are aligned to the input order regardless of provider ordering.
"""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

from src.shared.litellm_client import LiteLLMClient


def _embedding_response(
    pairs: list[tuple[int, list[float]]],
) -> SimpleNamespace:
    """A fake litellm embedding response: ``.data`` is a list of
    ``{"index", "embedding"}`` items (order as given)."""
    return SimpleNamespace(
        data=[{"index": i, "embedding": e} for i, e in pairs]
    )


async def test_embed_forwards_shape_and_orders_output() -> None:
    """embed() forwards model/input/api_key and restores input order by index."""
    client = LiteLLMClient(openai_api_key="oa-key")
    texts = ["alpha", "beta", "gamma"]
    # Provider returns the items OUT of order to prove we re-sort by index.
    resp = _embedding_response([(2, [0.3]), (0, [0.1]), (1, [0.2])])
    mock = AsyncMock(return_value=resp)

    with patch("litellm.aembedding", mock):
        out = await client.embed(
            texts=texts, model="openai/text-embedding-3-small"
        )

    # Aligned to the input order: alpha->[0.1], beta->[0.2], gamma->[0.3].
    assert out == [[0.1], [0.2], [0.3]]
    kwargs = mock.call_args.kwargs
    assert kwargs["model"] == "openai/text-embedding-3-small"
    assert kwargs["input"] == texts
    assert kwargs["api_key"] == "oa-key"


async def test_embed_resolves_key_from_model_prefix() -> None:
    """The provider key is selected by the model prefix (same rule as
    ``complete_structured``)."""
    client = LiteLLMClient(
        anthropic_api_key="an-key",
        openai_api_key="oa-key",
        gemini_api_key="gm-key",
    )
    resp = _embedding_response([(0, [1.0])])
    mock = AsyncMock(return_value=resp)

    with patch("litellm.aembedding", mock):
        await client.embed(texts=["x"], model="gemini/text-embedding-004")

    assert mock.call_args.kwargs["api_key"] == "gm-key"
