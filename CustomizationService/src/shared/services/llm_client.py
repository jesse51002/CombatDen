"""LiteLLMClient — the LLM contract implemented via litellm, calling
providers directly (no proxy hop)."""

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
from src.shared.services.cost import CostTracking, litellm_call_cost
from src.shared.services.provider_keys import provider_api_key

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


_INDENT = "  "


def _emit_scalar(prefix: str, value: Any, out: list[str], pad: str) -> None:
    """Append a scalar, splitting on real newlines so each line stands
    on its own (``str()`` keeps it total — an odd type never crashes it)."""
    text = value if isinstance(value, str) else str(value)
    head, *rest = text.split("\n")
    out.append(f"{pad}{prefix}{head}")
    out.extend(f"{pad}{line}" for line in rest)


def _emit(value: Any, out: list[str], indent: int) -> None:
    """Render one node into ``out`` with real newlines preserved."""
    pad = _INDENT * indent
    if isinstance(value, dict):
        if "role" in value and "content" in value:
            out.append(f"{pad}[{value['role']}]")
            _emit(value["content"], out, indent + 1)
            for key, val in value.items():
                if key in ("role", "content") or val in (None, "", [], {}):
                    continue
                out.append(f"{pad}{_INDENT}{key}:")
                _emit(val, out, indent + 2)
            return
        part_type = value.get("type")
        if part_type == "text":
            _emit_scalar("", value.get("text", ""), out, pad)
            return
        if part_type == "image_url":
            url = value.get("image_url", "")
            if isinstance(url, dict):
                url = url.get("url", "")
            _emit_scalar("<image> ", url, out, pad)
            return
        for key, val in value.items():
            if isinstance(val, (dict, list)):
                out.append(f"{pad}{key}:")
                _emit(val, out, indent + 1)
            else:
                _emit_scalar(f"{key}: ", val, out, pad)
        return
    if isinstance(value, list):
        for item in value:
            _emit(item, out, indent)
        return
    _emit_scalar("", value, out, pad)


def _render(value: Any) -> str:
    """Human-readable, newline-preserving dump for logs.

    JSON-encoding (the old approach) escaped the real newlines in
    ``.md``-templated prompts to literal ``\\n``, collapsing a prompt to
    one unreadable line in the CLI. This walks the structure and prints
    text with its line breaks intact; base64 image blobs are still
    elided via ``_loggable``. Total — an odd type never crashes it."""
    out: list[str] = []
    _emit(_loggable(value), out, 0)
    return "\n".join(out)


class LiteLLMClient(CostTracking, LLMClient):
    """Concrete LLM client that calls providers directly via litellm.

    Accumulates the USD cost of every call it makes (palette, image
    prompt, complexity, style check all route through here) via
    ``CostTracking``; the writer reads ``cost`` to build the run total.
    """

    @staticmethod
    def _api_key(model_name: str) -> str:
        """Resolve the provider key for a provider-routed model id
        (shared with the image generator via ``provider_keys``)."""
        return provider_api_key(model_name)

    def _completion_kwargs(self, model_name: str, messages: list[dict]) -> dict:
        """Base litellm kwargs for a direct provider call."""
        return {
            "model": model_name,
            "messages": messages,
            "api_key": self._api_key(model_name),
        }

    async def _acompletion(self, kwargs: dict, model_name: str) -> Any:
        """One litellm call; any SDK/transport failure → ``ProviderError``."""
        try:
            return await litellm.acompletion(**kwargs)
        except Exception as exc:
            raise ProviderError(
                f"completion failed for model {model_name!r}: {exc}"
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
        model: str,
        tools: list[dict] | None = None,
    ) -> dict:
        """One chat turn via litellm → the message dict. ``model`` is
        required and carries the provider prefix (litellm routes on it).
        Raises ``ProviderError`` on a transport/litellm failure."""

        """
        logger.debug(
            "complete input → %s:\n\n%s\n", model, _render(messages)
        )
        """
        kwargs = self._completion_kwargs(model, messages)
        if tools is not None:
            kwargs["tools"] = tools
        resp = await self._acompletion(kwargs, model)
        self._add_cost(litellm_call_cost(resp, model))
        message = resp.choices[0].message.model_dump()
        logger.debug("complete output ← %s:\n\n%s\n", model, _render(message))
        return message

    async def complete_structured(
        self,
        messages: list[dict],
        *,
        schema: type[ModelT],
        model: str,
    ) -> ModelT:
        """Constrained generation: schema in, model out. ``model`` is
        required and carries the provider prefix (litellm routes on it).

        A schema miss (parse/validation failure) is fed back and re-asked
        up to ``settings.llm_max_retries`` extra times, then raises
        ``SchemaValidationError``. ``ProviderError`` on a transport failure.
        """
        # defensive copy: never reshape the caller's list
        convo: list[dict] = list(messages)
        last_error: Exception | None = None

        for attempt in range(settings.llm_max_retries + 1):
            kwargs = self._completion_kwargs(model, convo)
            kwargs["response_format"] = schema

            logger.debug(
                "complete_structured input → %s %s (attempt %d):\n\n%s\n",
                model,
                schema.__name__,
                attempt + 1,
                _render(convo),
            )
            resp = await self._acompletion(kwargs, model)
            # Every attempt is a billed call — count each, not just the
            # one that finally validates.
            self._add_cost(litellm_call_cost(resp, model))
            content = self._message_content(resp.choices[0].message)
            try:
                parsed = schema.model_validate_json(content)
                logger.debug(
                    "complete_structured output ← %s %s (validated):\n\n%s\n",
                    model,
                    schema.__name__,
                    _render(parsed.model_dump()),
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
