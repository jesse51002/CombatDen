"""IconSetCatalog — the async curated-icon-set catalog contract.

An icon *set* is an app-agnostic shared resource (like the Google Fonts
catalog): a curated library of monochrome SVGs with a name, a long "vibe"
style description, and a list of the icon short-names it contains. The
icon module uses the catalog in three places:

- The set-selection call lists every set's id / name / vibe so the LLM
  can pick the best-fit set for the brand.
- The matching call is constrained to the chosen set's icon names.
- After matching, ``icon_path`` resolves a matched icon's on-disk SVG so
  the node can copy it into the run output dir.

The interface is deliberately tiny — concrete implementations decide how
to load and cache. ``IconSetCatalogEntry`` is the per-set metadata the
rest of the pipeline cares about; it mirrors the curated ``set.yaml``
shape minus anything the pipeline never reads.
"""

from __future__ import annotations

import re
from abc import ABC, abstractmethod

from pydantic import BaseModel, ConfigDict, field_validator

from schema.primitives import AbsolutePath

_ID_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")


class IconSetCatalogEntry(BaseModel):
    """One curated icon set's metadata, as the pipeline reads it.

    Mirrors the on-disk ``set.yaml``: ``id`` (snake_case, matches the set
    directory name), ``name`` (human display label), ``vibe`` (the long
    style description fed into the set-selection prompt), and ``icons``
    (the short-names the set contains — each must have a matching ``.svg``
    on disk, which the concrete catalog checks, not this model).

    ``extra="ignore"`` so a curated ``set.yaml`` can carry presentation
    keys the pipeline doesn't read (licence, author, homepage) without
    breaking validation.
    """

    model_config = ConfigDict(extra="ignore")

    id: str
    name: str
    vibe: str
    icons: list[str]

    @field_validator("id")
    @classmethod
    def _id_is_snake_case(cls, v: str) -> str:
        if not _ID_PATTERN.match(v):
            raise ValueError(
                f"icon set id {v!r} must be snake_case "
                "(lowercase, digits, underscores; must start with a letter)"
            )
        return v

    @field_validator("name", "vibe")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("icon set field must be non-empty")
        return v


class IconSetCatalog(ABC):
    """Async curated-icon-set catalog (contract only)."""

    @abstractmethod
    async def sets(self) -> list[IconSetCatalogEntry]:
        """Every known icon set's metadata (id, name, vibe, icon names).

        The set-selection prompt describes each, and the matching closed
        response model is constrained to the chosen set's icon names.
        """
        raise NotImplementedError

    @abstractmethod
    async def lookup(self, set_id: str) -> IconSetCatalogEntry | None:
        """One set's metadata, or ``None`` if no such set is known."""
        raise NotImplementedError

    @abstractmethod
    async def icon_path(
        self, set_id: str, icon_name: str
    ) -> AbsolutePath | None:
        """Absolute path of one matched icon's SVG, or ``None`` if the
        set or icon doesn't exist. The node copies this into the run dir;
        the catalog only resolves the source path."""
        raise NotImplementedError
