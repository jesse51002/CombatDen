"""ImageGenerator — the async image-generation contract."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path

from schema import AbsolutePath


class ImageGenerator(ABC):
    """Generate one image from a prompt (contract only)."""

    @abstractmethod
    async def generate(self, prompt: str, dest: Path) -> AbsolutePath:
        """Generate -> write PNG at `dest` -> return its absolute path."""
        raise NotImplementedError
