"""LLMClient — the async LLM contract modules depend on."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TypeVar

from pydantic import BaseModel

ModelT = TypeVar("ModelT", bound=BaseModel)


class LLMClient(ABC):
    """Async LLM caller (contract only)."""

    @abstractmethod
    async def complete(
        self,
        messages: list[dict],
        *,
        model: str,
        tools: list[dict] | None = None,
    ) -> dict:
        """Run one chat turn. ``model`` is required and carries the
        provider prefix the client routes on."""
        raise NotImplementedError

    @abstractmethod
    async def complete_structured(
        self,
        messages: list[dict],
        *,
        schema: type[ModelT],
        model: str,
        image_urls: list[str] | None = None,
    ) -> ModelT:
        """Constrained generation: a Pydantic schema in, a model out.

        ``model`` is required and carries the provider prefix the client
        routes on. When ``image_urls`` is set the implementation attaches the
        images to the user message as a multimodal (vision) call.

        Raises:
            SchemaValidationError: output never validated within the
                implementation's retry budget.
        """
        raise NotImplementedError
