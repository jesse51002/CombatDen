"""ImageGenerator — the async image-generation contract."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from schema import AbsolutePath


class ImageGenerator(ABC):
    """Generate or edit one image (contract only).

    Both are litellm image calls and share key resolution and payload
    handling, so they live on one contract — like ``LLMClient`` carrying
    both ``complete`` and ``complete_structured``.
    """

    @abstractmethod
    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> AbsolutePath:
        """Generate -> write PNG at `dest` -> return its absolute path.

        ``model`` is a per-call concern (provider-prefixed, like the LLM
        client routes on); ``quality`` is the model's quality tier.
        """
        raise NotImplementedError

    @abstractmethod
    async def edit(
        self, src: Path, instruction: str, dest: Path, *, model: str
    ) -> AbsolutePath:
        """Edit `src` per `instruction` -> write PNG at `dest` -> return
        its absolute path.

        ``model`` is a per-call concern (provider-prefixed); ``instruction``
        states only what to change.
        """
        raise NotImplementedError
