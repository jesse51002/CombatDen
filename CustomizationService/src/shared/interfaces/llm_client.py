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
    ) -> ModelT:
        """Constrained generation: a Pydantic schema in, a model out.

        ``model`` is required and carries the provider prefix the client
        routes on.

        Raises:
            SchemaValidationError: output never validated within
                ``settings.llm_max_retries`` extra attempts.
        """
        raise NotImplementedError

    @property
    @abstractmethod
    def cost(self) -> float:
        """Running USD this client has spent this run (the writer sums it)."""
        raise NotImplementedError
