"""ProxyLLMClient — the LLM contract implemented against the LiteLLM Proxy."""

from __future__ import annotations

import json
import logging
from pathlib import Path
from string import Template
from typing import Any

import litellm
from pydantic import ValidationError

from src.core.config import settings
from src.core.errors import ProviderError, SchemaValidationError
from src.shared.interfaces.llm_client import LLMClient, ModelT

logger = logging.getLogger(__name__)

SCHEMA_CORRECTION_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "schema_correction.md"
)

# Logged prompts elide base64 data URLs so a vision call's image payload
# isn't dumped into the logs.
DATA_URL_MARKER = ";base64,"


def _loggable(value: Any) -> Any:
    """Recursive copy of messages with base64 data URLs elided for logging.

    Keeps every text part intact; replaces only the image blob so a
    vision-call payload logs as ``data:image/png;base64,<N chars elided>``.
    """
    if isinstance(value, dict):
        return {k: _loggable(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_loggable(item) for item in value]
    if isinstance(value, str) and DATA_URL_MARKER in value:
        prefix = value.split(DATA_URL_MARKER, 1)[0]
        return f"{prefix}{DATA_URL_MARKER}<{len(value)} chars elided>"
    return value


class ProxyLLMClient(LLMClient):
    """Concrete LLM client that talks only to the LiteLLM Proxy."""

    def _proxy_kwargs(
        self, model_name: str, messages: list[dict]
    ) -> dict:
        """Base litellm kwargs aiming every call at the proxy."""
        return {
            "model": f"litellm_proxy/{model_name}",
            "messages": messages,
            "api_base": settings.litellm_proxy_url,
            "api_key": settings.litellm_proxy_key,
        }

    async def _acompletion(
        self, kwargs: dict, model_name: str
    ) -> Any:
        """One proxy call; any SDK/transport failure → ``ProviderError``."""
        try:
            return await litellm.acompletion(**kwargs)
        except Exception as exc:
            raise ProviderError(
                f"proxy completion failed for model {model_name!r}: {exc}"
            ) from exc

    @staticmethod
    def _message_content(message: Any) -> str:
        """Pull the text content off a litellm message."""
        try:
            return message["content"]
        except (TypeError, KeyError):
            return message.content

    @staticmethod
    def _correction_turns(content: str, error: Exception) -> list[dict]:
        """Assistant echo + corrective user turn (wording in
        ``schema_correction.md``; ``safe_substitute`` tolerates stray ``$``)."""
        template = SCHEMA_CORRECTION_PROMPT_PATH.read_text(encoding="utf-8")
        return [
            {"role": "assistant", "content": content},
            {
                "role": "user",
                "content": Template(template).safe_substitute(error=error),
            },
        ]

    async def complete(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        model: str | None = None,
    ) -> dict:
        """One chat turn against the proxy → the message dict.
        Raises ``ProviderError`` on a transport/litellm failure."""
        model_name = model or settings.text_model
        logger.debug(
            "complete input → %s:\n\n%s\n", model_name, _loggable(messages)
        )
        kwargs = self._proxy_kwargs(model_name, messages)
        if tools is not None:
            kwargs["tools"] = tools
        resp = await self._acompletion(kwargs, model_name)
        message = resp.choices[0].message.model_dump()
        logger.debug(
            "complete output ← %s:\n\n%s\n", model_name, _loggable(message)
        )
        return message

    async def complete_structured(
        self,
        messages: list[dict],
        *,
        schema: type[ModelT],
        model: str | None = None,
    ) -> ModelT:
        """Constrained generation: schema in, model out.

        A schema miss (parse/validation failure) is fed back and re-asked
        up to ``settings.llm_max_retries`` extra times, then raises
        ``SchemaValidationError``. ``ProviderError`` on a transport failure.
        """
        model_name = model or settings.text_model
        # defensive copy: never reshape the caller's list
        convo: list[dict] = list(messages)
        last_error: Exception | None = None

        for attempt in range(settings.llm_max_retries + 1):
            kwargs = self._proxy_kwargs(model_name, convo)
            kwargs["response_format"] = schema

            logger.debug(
                "complete_structured input → %s %s (attempt %d):\n\n%s\n",
                model_name,
                schema.__name__,
                attempt + 1,
                _loggable(convo),
            )
            resp = await self._acompletion(kwargs, model_name)
            content = self._message_content(resp.choices[0].message)
            try:
                parsed = schema.model_validate_json(content)
                logger.debug(
                    "complete_structured output ← %s %s (validated):\n\n%s\n",
                    model_name,
                    schema.__name__,
                    parsed.model_dump_json(),
                )
                return parsed
            except (
                ValidationError,
                ValueError,
                json.JSONDecodeError,
            ) as exc:
                last_error = exc
                logger.debug(
                    "complete_structured miss for %s: %s",
                    schema.__name__,
                    exc,
                )
                convo = convo + self._correction_turns(content, exc)

        raise SchemaValidationError(
            f"{schema.__name__} never validated after "
            f"{settings.llm_max_retries + 1} attempts"
        ) from last_error
