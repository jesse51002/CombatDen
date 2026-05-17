"""LLMClient — the async LLM contract modules depend on."""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TypeVar

from pydantic import BaseModel

ModelT = TypeVar("ModelT", bound=BaseModel)


class LLMClient(ABC):
    """Async, proxy-backed LLM caller (contract only)."""

    @abstractmethod
    async def complete(
        self,
        messages: list[dict],
        *,
        tools: list[dict] | None = None,
        model: str | None = None,
    ) -> dict:
        """Run one chat turn."""
        raise NotImplementedError

    @abstractmethod
    async def complete_structured(
        self,
        messages: list[dict],
        *,
        schema: type[ModelT],
        model: str | None = None,
    ) -> ModelT:
        """Constrained generation: a Pydantic schema in, a model out.

        Raises:
            SchemaValidationError: output never validated within
                ``settings.llm_max_retries`` extra attempts.
        """
        raise NotImplementedError
