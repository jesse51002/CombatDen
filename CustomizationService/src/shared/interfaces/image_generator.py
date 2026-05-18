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

        Text-to-image: no input image. When the result must contain a
        specific input image (a DIRECT image dependency) use ``compose``
        instead.
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

    @abstractmethod
    async def compose(
        self,
        prompt: str,
        srcs: list[Path],
        dest: Path,
        *,
        model: str,
        quality: str,
    ) -> AbsolutePath:
        """Generate a NEW image conditioned on one or more input images
        -> write PNG at `dest` -> return its absolute path.

        ``prompt`` is the full generation instruction; ``srcs`` are the
        input image(s) the result must contain or build on — a DIRECT
        image dependency. Unlike ``edit`` (a narrow corrective pass that
        changes only what is stated), this is generation: the result is a
        new image, ``prompt`` describes it in full, and ``quality`` is the
        model's quality tier (parity with ``generate``). ``model`` is a
        per-call concern (provider-prefixed).
        """
        raise NotImplementedError

    @property
    @abstractmethod
    def cost(self) -> float:
        """Running USD spent this run on generation + edits (writer sums it)."""
        raise NotImplementedError
