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
        self, prompt: str, dest: Path, *, model: str, quality: str | None = None
    ) -> AbsolutePath:
        """Generate -> write the image at `dest` -> return its absolute path.

        ``model`` is a per-call concern (provider-prefixed, like the LLM
        client routes on). ``quality`` is the model's quality tier and is
        OPTIONAL: raster generators (gpt-image) use it; generators with no
        quality tier (Recraft vector/SVG) leave it ``None``.
        Text-to-image: no input image.
        """
        raise NotImplementedError

    async def edit(
        self,
        prompt: str,
        source: Path,
        dest: Path,
        *,
        model: str,
        quality: str | None = None,
    ) -> AbsolutePath:
        """Image-to-image: edit ``source`` per ``prompt`` → write ``dest`` →
        return its absolute path.

        Unlike ``generate`` (text-to-image), the prompt describes ONLY the
        change to make to ``source`` (e.g. "make the background darker"), not
        the whole desired scene. Optional on the contract: a generator with no
        edit endpoint leaves this unimplemented (the default raises).
        """
        raise NotImplementedError(
            f"{type(self).__name__} does not support image editing"
        )

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
