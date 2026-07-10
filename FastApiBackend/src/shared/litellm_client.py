"""LiteLLMClient — structured-output LLM calls via litellm.

Used by ``VideoQueryGenerator`` and ``VideoFeedRefiner`` for single-shot
structured calls. Provider keys are passed in at construction and forwarded
explicitly to litellm — ``os.environ`` is never touched.
"""

from __future__ import annotations

import json
import logging
from typing import Any, TypeVar

import litellm
from pydantic import BaseModel, ValidationError

logger = logging.getLogger(__name__)

# Suppress litellm's startup banners (printed to stderr regardless of log level).
litellm.suppress_debug_info = True

# Max total LLM attempts (1 initial + retries on schema validation miss).
_MAX_ATTEMPTS = 3

# Per-request transport timeout in seconds.
_REQUEST_TIMEOUT = 60.0

BaseModelT = TypeVar("BaseModelT", bound=BaseModel)


class LLMStructuredOutputError(Exception):
    """The LLM failed to produce a valid structured output after all retries."""


class LiteLLMClient:
    """Thin litellm wrapper for single-shot structured LLM calls.

    Provider keys are passed in at construction and forwarded explicitly to
    litellm via the ``api_key`` kwarg — ``os.environ`` is never written.
    The model string uses the litellm ``provider/name`` format (e.g.
    ``anthropic/claude-sonnet-4-6``); the prefix drives which key is used.
    """

    def __init__(
        self,
        *,
        anthropic_api_key: str = "",
        openai_api_key: str = "",
        gemini_api_key: str = "",
    ) -> None:
        self._anthropic_api_key = anthropic_api_key
        self._openai_api_key = openai_api_key
        self._gemini_api_key = gemini_api_key

    def _api_key_for_model(self, model: str) -> str | None:
        """Return the provider API key for a litellm model string, or None."""
        if model.startswith("anthropic/"):
            return self._anthropic_api_key or None
        if model.startswith("openai/"):
            return self._openai_api_key or None
        if model.startswith(("gemini/", "google/")):
            return self._gemini_api_key or None
        return None

    async def complete_structured(
        self,
        *,
        prompt: str,
        schema: type[BaseModelT],
        model: str,
    ) -> BaseModelT:
        """Single structured LLM call with a validate-and-retry loop.

        Calls ``litellm.acompletion`` with ``response_format=schema``, then
        parses ``choices[0].message.content`` as JSON into ``schema``. On a
        validation miss the attempt is logged and retried; after
        ``_MAX_ATTEMPTS`` failures a ``LLMStructuredOutputError`` is raised.
        """
        messages = [{"role": "user", "content": prompt}]
        api_key = self._api_key_for_model(model)
        last_error: Exception | None = None

        for attempt in range(_MAX_ATTEMPTS):
            resp = await litellm.acompletion(
                model=model,
                messages=messages,
                response_format=schema,
                api_key=api_key,
                timeout=_REQUEST_TIMEOUT,
            )
            content: str = resp.choices[0].message.content
            try:
                return schema.model_validate_json(content)
            except (ValidationError, ValueError, json.JSONDecodeError) as exc:
                last_error = exc
                logger.warning(
                    "complete_structured: %s validation miss (attempt %d/%d): %s",
                    schema.__name__,
                    attempt + 1,
                    _MAX_ATTEMPTS,
                    exc,
                )

        raise LLMStructuredOutputError(
            f"{schema.__name__} never validated after {_MAX_ATTEMPTS} attempts"
        ) from last_error

    async def embed(
        self,
        *,
        texts: list[str],
        model: str,
    ) -> list[list[float]]:
        """Embed a batch of texts, returning one vector per input in input order.

        Calls ``litellm.aembedding(model=..., input=texts)`` with the provider
        key resolved from the model prefix (same rule as
        :meth:`complete_structured`). The response's per-item ``index`` is used
        to restore the original input order regardless of how the provider
        returns them.

        Args:
            texts: The input strings to embed (one vector produced per string).
            model: A litellm ``provider/name`` model string (e.g.
                ``openai/text-embedding-3-small``); the prefix selects the key.

        Returns:
            A list of embedding vectors aligned to ``texts`` (``result[i]`` is
            the embedding of ``texts[i]``).
        """
        api_key = self._api_key_for_model(model)
        resp = await litellm.aembedding(
            model=model,
            input=texts,
            api_key=api_key,
            timeout=_REQUEST_TIMEOUT,
        )
        ordered = sorted(
            (self._embedding_item(item) for item in resp.data),
            key=lambda pair: pair[0],
        )
        return [embedding for _, embedding in ordered]

    @staticmethod
    def _embedding_item(item: Any) -> tuple[int, list[float]]:
        """(index, embedding) off one litellm embedding datum, tolerant of dict
        OR attribute access across litellm response shapes (some versions return
        plain dicts, some return objects). Mirrors VideoService's sibling
        ``WorkerEnricher``/``LLMClient`` helper so both sides survive either shape
        instead of raising ``TypeError`` on object data. Preserves the
        sort-by-index that restores input order."""
        if isinstance(item, dict):
            return item["index"], item["embedding"]
        return item.index, item.embedding
