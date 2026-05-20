"""GoogleFontsCatalog — the async Google Fonts catalog contract.

The catalog is used in two places:

- The font module's selection retry loop validates that the LLM's pick
  is a real Google Font family by calling ``contains``.
- The font delivery API endpoint resolves a chosen family's per-variant
  font-file URLs by calling ``lookup`` (the Developer API returns TTF
  URLs; the CSS2 endpoint serves woff2 to browsers separately).

The interface is deliberately tiny — both callers only need "is this a
real family" and "give me its files". Concrete implementations decide
how to fetch and cache.
"""

from __future__ import annotations

from abc import ABC, abstractmethod

from pydantic import BaseModel, ConfigDict


class GoogleFontMetadata(BaseModel):
    """One Google Font entry as the rest of the pipeline cares about it.

    Fields mirror the Google Fonts Developer API response, minus the bits
    the pipeline never reads (``kind``, ``lastModified``, ``subsets``,
    ``axes``, ``menu``). ``files`` keys are variant labels Google uses
    (``"regular"``, ``"700"``, ``"italic"``, ``"700italic"``, …) mapped
    to ``https://fonts.gstatic.com/...`` TTF URLs (the Developer API
    serves TTF; the CSS2 endpoint serves woff2 under a browser
    user-agent). Every consumer — web, Flutter, native — can load TTF,
    so these URLs are the frontend-agnostic delivery target.
    """

    model_config = ConfigDict(extra="ignore")

    family: str
    category: str
    variants: list[str]
    files: dict[str, str]


class GoogleFontsCatalog(ABC):
    """Async Google Fonts catalog (contract only)."""

    @abstractmethod
    async def contains(self, family: str) -> bool:
        """True iff ``family`` is a known Google Fonts family.

        Matching is case-insensitive — the LLM may not nail the
        canonical capitalisation, and a near-miss is the same family
        from the user's perspective.
        """
        raise NotImplementedError

    @abstractmethod
    async def lookup(self, family: str) -> GoogleFontMetadata | None:
        """The full catalog entry for ``family``, or ``None`` if unknown.

        Matching is case-insensitive (see ``contains``). The returned
        ``family`` field carries Google's canonical capitalisation —
        callers should prefer it over whatever the user typed.
        """
        raise NotImplementedError

    @abstractmethod
    async def families(self) -> frozenset[str]:
        """Every known family name, lowercased — a snapshot.

        The font selection retry loop builds a per-request Pydantic
        response model whose sync ``model_validator`` checks each picked
        family against this set. The validator can't await the catalog
        itself, so the caller awaits the snapshot once and feeds the
        closed set into the model factory.
        """
        raise NotImplementedError
