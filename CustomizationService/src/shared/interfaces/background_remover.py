"""BackgroundRemover — the async background-removal contract."""

from __future__ import annotations

from abc import ABC, abstractmethod
from pathlib import Path


class BackgroundRemover(ABC):
    """Turn a solid-background image into a transparent cutout (contract)."""

    @abstractmethod
    async def remove(self, src: Path, dst: Path) -> None:
        """Read ``src``, strip its background, write the RGBA cutout to ``dst``."""
        raise NotImplementedError

    @property
    @abstractmethod
    def cost(self) -> float:
        """Running USD spent this run on background removal (writer sums it)."""
        raise NotImplementedError
