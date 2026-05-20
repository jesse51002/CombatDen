"""ImageGenerator — the async image-generation contract."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from schema import AbsolutePath


class ImageGenerator(ABC):
    """Generate one image from a prompt (contract only).

    Text-to-image only — like ``LLMClient`` for the image side. Declared
    image dependencies are reference, folded into the prompt text by the
    caller; nothing is fed in as an input image.
    """

    @abstractmethod
    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> AbsolutePath:
        """Generate -> write PNG at `dest` -> return its absolute path.

        ``model`` is a per-call concern (provider-prefixed, like the LLM
        client routes on); ``quality`` is the model's quality tier.
        Text-to-image: no input image.
        """
        raise NotImplementedError

    @property
    @abstractmethod
    def cost(self) -> float:
        """Running USD spent this run on generation (the writer sums it)."""
        raise NotImplementedError

    @property
    @abstractmethod
    def cost_by_model(self) -> dict[str, float]:
        """The same running spend, split per model id (the writer merges it)."""
        raise NotImplementedError
