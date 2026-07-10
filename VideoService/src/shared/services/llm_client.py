"""LiteLLMClient — the LLM contract implemented via litellm, calling
providers directly (no proxy hop).

Originally copied from ``CustomizationService/src/shared/services/llm_client.py``
(imports rewritten for this service). The classification pass uses
``complete_structured`` (batch cost accrues on ``self.cost``); the video worker
adds three capabilities that RETURN cost per call instead of stashing it on the
shared instance (concurrency-safe):

- ``complete_structured`` gains an optional ``image_urls`` arg for multimodal
  (vision) calls — the last user message becomes litellm multi-part content.
- ``complete_structured_with_cost`` — same call, returns ``(parsed, cost_usd)``.
- ``embed`` — ``litellm.aembedding`` wrapper returning ``(vectors, cost_usd)``.
"""

from __future__ import annotations

import asyncio
import json
import logging
from collections.abc import Callable
from pathlib import Path
from string import Template
from typing import Any

import litellm
from pydantic import ValidationError

from src.core.errors import ProviderError, SchemaValidationError
from src.shared.interfaces.llm_client import LLMClient, ModelT
from src.shared.services.provider_keys import provider_api_key

logger = logging.getLogger(__name__)

# Silence litellm's printed "Give Feedback / Get Help" + provider-list banners
# (these go to stderr regardless of log level). Log *levels* are controlled
# centrally by the caller (the classify pass runs everything at WARNING and only
# its own logger at DEBUG), so litellm's per-call INFO is already filtered there.
litellm.suppress_debug_info = True

SCHEMA_CORRECTION_PROMPT_PATH = (
    Path(__file__).parent / "prompts" / "schema_correction.md"
)

# Defaults for the three instance knobs below (``LiteLLMClient.__init__``). A
# caller that wants different values (the worker, from ``WorkerSettings``)
# passes them explicitly; everyone else (tests, the classify pass) gets these.
#
# Backoff (seconds) before each schema re-ask after a miss: wait 5s, then 15s.
# Its length is the retry budget — len + 1 total attempts (here: 3).
DEFAULT_RETRY_BACKOFF_SECONDS = (5, 15)

# Transport-level retries (litellm's own exponential backoff) for transient
# provider failures — chiefly Gemini RateLimitError under the classify fan-out,
# which otherwise drops the tag outright. Distinct from the schema-correction
# re-asks above (those handle a bad *response*, not a failed *call*). Genuine
# 400s (BadRequest) are not retried by litellm. Passed on EVERY completion/embed
# call below (they were previously defined but never wired — so calls ran with
# no retries AND no timeout, letting a hung Gemini connection stall a whole
# gather forever).
DEFAULT_LLM_NUM_RETRIES = 5
# Per-attempt request timeout. A hung provider connection otherwise blocks the
# awaiting task indefinitely (no timeout → asyncio.gather freezes on it → the
# whole enrich chunk stalls). Generous enough not to cut a legitimately slow
# multimodal call; a true hang times out → retries → finally strikes the video.
DEFAULT_REQUEST_TIMEOUT_SECONDS = 90

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


def _call_cost(resp: Any, model: str) -> float:
    """USD for one litellm response via litellm's own model pricing; ``0.0``
    (logged) if it can't price the call — a missing price never derails the
    running total. Output here is tiny, so input tokens dominate the cost."""
    try:
        cost = litellm.completion_cost(completion_response=resp, model=model)
        return float(cost) if cost else 0.0
    except Exception as exc:  # noqa: BLE001 — unpriceable ⇒ count 0, never crash
        logger.debug("litellm could not price %s call: %s", model, exc)
        return 0.0


class LiteLLMClient(LLMClient):
    """Concrete LLM client that calls providers directly via litellm. Tracks a
    running USD estimate of every call it makes (litellm's own pricing).

    ``timeout_seconds`` / ``num_retries`` / ``retry_backoff`` default to this
    module's ``DEFAULT_*`` constants but are overridable per instance — kept
    here (not read from a ``Settings`` object) so this shared module never
    imports ``src.worker`` (layering: shared → worker is one-way). The worker's
    construction sites pass ``WorkerSettings`` values instead of the defaults.
    """

    def __init__(
        self,
        *,
        timeout_seconds: float = DEFAULT_REQUEST_TIMEOUT_SECONDS,
        num_retries: int = DEFAULT_LLM_NUM_RETRIES,
        retry_backoff: tuple[int, ...] = DEFAULT_RETRY_BACKOFF_SECONDS,
    ) -> None:
        self._timeout_seconds = timeout_seconds
        self._num_retries = num_retries
        self._retry_backoff = retry_backoff

    @property
    def cost(self) -> float:
        """Running USD spent this run, via litellm's pricing. Lazily
        initialises ``_cost`` on first bump."""
        return getattr(self, "_cost", 0.0)

    def _bump_cost(self, cost: float) -> None:
        """Add one attempt's USD to the running instance total. Used only by
        the cost-tracking ``complete`` / ``complete_structured`` batch path;
        ``*_with_cost`` and ``embed`` return their cost instead of stashing it."""
        self._cost = self.cost + cost

    @staticmethod
    def _api_key(model_name: str) -> str:
        """Resolve the provider key for a provider-routed model id."""
        return provider_api_key(model_name)

    def _completion_kwargs(self, model_name: str, messages: list[dict]) -> dict:
        """Base litellm kwargs for a direct provider call."""
        return {
            "model": model_name,
            "messages": messages,
            "api_key": self._api_key(model_name),
            "timeout": self._timeout_seconds,
            "num_retries": self._num_retries,
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

    @staticmethod
    def _attach_images(
        messages: list[dict],
        image_urls: list[str] | None,
    ) -> list[dict]:
        """Rebuild the last user message into litellm multi-part content when
        ``image_urls`` is given; a no-op (the same list) otherwise.

        Returns a NEW list — the caller's messages are never mutated. Text
        stays first, then one ``image_url`` part per URL::

            [{"type": "text", "text": <prompt>},
             {"type": "image_url", "image_url": {"url": <url>}}, ...]

        Raises ``ValueError`` when images are supplied but no user message
        exists to carry them.
        """
        if not image_urls:
            return messages
        convo = [dict(message) for message in messages]
        for message in reversed(convo):
            if message.get("role") != "user":
                continue
            content = message.get("content", "")
            parts: list[dict] = (
                list(content)
                if isinstance(content, list)
                else [{"type": "text", "text": content}]
            )
            parts.extend(
                {"type": "image_url", "image_url": {"url": url}}
                for url in image_urls
            )
            message["content"] = parts
            return convo
        raise ValueError(
            "image_urls supplied but no user message to attach them to"
        )

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
        kwargs = self._completion_kwargs(model, messages)
        if tools is not None:
            kwargs["tools"] = tools
        resp = await self._acompletion(kwargs, model)
        self._bump_cost(_call_cost(resp, model))
        message = resp.choices[0].message.model_dump()
        logger.debug("complete output ← %s:\n\n%s\n", model, _render(message))
        return message

    async def _run_structured(
        self,
        convo: list[dict],
        schema: type[ModelT],
        model: str,
        record_cost: Callable[[float], None],
    ) -> ModelT:
        """Shared constrained-generation retry loop.

        Runs the call, validates the reply against ``schema``, and re-asks on a
        miss (backing off ``self._retry_backoff`` — 5s, then 15s by default).
        Every billed attempt (success *or* miss) invokes ``record_cost`` with
        that attempt's USD, so this core never touches instance state — the
        caller decides whether to stash the cost or return it.

        Raises ``SchemaValidationError`` when no attempt validates, or
        ``ProviderError`` on a transport failure.
        """
        last_error: Exception | None = None
        total_attempts = len(self._retry_backoff) + 1

        for attempt in range(total_attempts):
            kwargs = self._completion_kwargs(model, convo)
            kwargs["response_format"] = schema

            resp = await self._acompletion(kwargs, model)
            # Every attempt is a billed call — record each, not just the
            # one that finally validates.
            record_cost(_call_cost(resp, model))
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
                convo = convo + self._correction_turns(content, exc)
                # No backoff after the final attempt — fall through to raise.
                if attempt < len(self._retry_backoff):
                    wait = self._retry_backoff[attempt]
                    logger.warning(
                        "%s schema miss (attempt %d/%d): %s — retrying in %ds",
                        schema.__name__,
                        attempt + 1,
                        total_attempts,
                        exc,
                        wait,
                    )
                    await asyncio.sleep(wait)

        raise SchemaValidationError(
            f"{schema.__name__} never validated after {total_attempts} attempts"
        ) from last_error

    async def complete_structured(
        self,
        messages: list[dict],
        *,
        schema: type[ModelT],
        model: str,
        image_urls: list[str] | None = None,
    ) -> ModelT:
        """Constrained generation: schema in, model out. ``model`` is
        required and carries the provider prefix (litellm routes on it).

        When ``image_urls`` is set, the last user message's content is rebuilt
        into litellm's multi-part ``[{"type": "text", ...}, {"type":
        "image_url", ...}]`` shape (a vision call). A schema miss is fed back and
        re-asked, backing off ``self._retry_backoff`` (5s, then 15s by default),
        then raises ``SchemaValidationError``; ``ProviderError`` on a transport
        failure.

        Cost is accumulated on the instance (``self.cost``) for the existing
        batch callers; use ``complete_structured_with_cost`` to get the cost
        back per call instead.
        """
        convo = self._attach_images(list(messages), image_urls)
        return await self._run_structured(
            convo, schema, model, self._bump_cost
        )

    async def complete_structured_with_cost(
        self,
        messages: list[dict],
        *,
        schema: type[ModelT],
        model: str,
        image_urls: list[str] | None = None,
    ) -> tuple[ModelT, float]:
        """Like ``complete_structured`` but RETURNS ``(parsed, cost_usd)`` and
        never stashes cost on the shared instance (concurrency-safe).

        ``cost_usd`` sums every billed attempt (schema-correction re-asks
        included). Same ``image_urls`` multimodal behaviour and same raises.
        """
        convo = self._attach_images(list(messages), image_urls)
        costs: list[float] = []
        parsed = await self._run_structured(
            convo, schema, model, costs.append
        )
        return parsed, sum(costs)

    async def embed(
        self,
        texts: list[str],
        model: str,
    ) -> tuple[list[list[float]], float]:
        """Embed ``texts`` via ``litellm.aembedding`` → ``(vectors, cost_usd)``.

        Vectors come back in input order. ``model`` carries the provider prefix
        (e.g. ``openai/text-embedding-3-small``); its key is resolved exactly as
        the completion path does. Cost is RETURNED, never stashed on the shared
        instance (concurrency-safe). Raises ``ProviderError`` on a transport
        failure.
        """
        try:
            resp = await litellm.aembedding(
                model=model,
                input=texts,
                api_key=self._api_key(model),
                timeout=self._timeout_seconds,
                num_retries=self._num_retries,
            )
        except Exception as exc:
            raise ProviderError(
                f"embedding failed for model {model!r}: {exc}"
            ) from exc
        ordered = sorted(
            (self._embedding_item(item) for item in resp.data),
            key=lambda pair: pair[0],
        )
        vectors = [embedding for _, embedding in ordered]
        return vectors, _call_cost(resp, model)

    @staticmethod
    def _embedding_item(item: Any) -> tuple[int, list[float]]:
        """(index, embedding) off one litellm embedding datum, tolerant of
        dict or attribute access across litellm response shapes."""
        if isinstance(item, dict):
            return item["index"], item["embedding"]
        return item.index, item.embedding
