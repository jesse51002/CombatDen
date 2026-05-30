"""Unit tests for LocalIconSetCatalog: lazy load, sets/lookup/icon_path,
and the malformed-manifest error path."""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest

from src.core.errors import ProviderError
from src.shared.services.local_icon_set_catalog import LocalIconSetCatalog


def _write_set(
    root: Path,
    set_id: str,
    *,
    name: str,
    icons: list[str],
    manifest: str | None = None,
) -> None:
    """Create ``root/<set_id>/set.yaml`` + ``icons/<name>.svg`` files."""
    set_dir = root / set_id
    icons_dir = set_dir / "icons"
    icons_dir.mkdir(parents=True, exist_ok=True)
    if manifest is None:
        names = "\n".join(f"  - {n}" for n in icons)
        manifest = (
            f"id: {set_id}\nname: {name}\n"
            f"vibe: a clean test set\nicons:\n{names}\n"
        )
    (set_dir / "set.yaml").write_text(manifest, encoding="utf-8")
    for n in icons:
        (icons_dir / f"{n}.svg").write_text("<svg/>", encoding="utf-8")


def test_sets_loads_every_manifest(tmp_path: Path) -> None:
    _write_set(tmp_path, "lucide_lite", name="Lucide Lite", icons=["home", "search"])
    _write_set(tmp_path, "solid_bold", name="Solid Bold", icons=["star"])

    cat = LocalIconSetCatalog(tmp_path)
    sets = asyncio.run(cat.sets())

    by_id = {s.id: s for s in sets}
    assert set(by_id) == {"lucide_lite", "solid_bold"}
    assert by_id["lucide_lite"].name == "Lucide Lite"
    assert by_id["lucide_lite"].icons == ["home", "search"]


def test_lookup_hit_and_miss(tmp_path: Path) -> None:
    _write_set(tmp_path, "lucide_lite", name="Lucide Lite", icons=["home"])
    cat = LocalIconSetCatalog(tmp_path)

    entry = asyncio.run(cat.lookup("lucide_lite"))
    assert entry is not None and entry.name == "Lucide Lite"
    assert asyncio.run(cat.lookup("does_not_exist")) is None


def test_icon_path_hit_and_miss(tmp_path: Path) -> None:
    _write_set(tmp_path, "lucide_lite", name="Lucide Lite", icons=["home"])
    cat = LocalIconSetCatalog(tmp_path)

    hit = asyncio.run(cat.icon_path("lucide_lite", "home"))
    assert hit is not None
    p = Path(str(hit))
    assert p.is_absolute() and p.is_file() and p.name == "home.svg"

    # Unknown icon in a known set, and a known icon in an unknown set.
    assert asyncio.run(cat.icon_path("lucide_lite", "rocket")) is None
    assert asyncio.run(cat.icon_path("nope", "home")) is None


def test_empty_root_yields_no_sets(tmp_path: Path) -> None:
    """A missing/empty catalog dir is not an error — just no sets."""
    cat = LocalIconSetCatalog(tmp_path / "absent")
    assert asyncio.run(cat.sets()) == []


def test_malformed_manifest_raises_provider_error(tmp_path: Path) -> None:
    # ``vibe`` is required and non-empty — omit it to fail validation.
    _write_set(
        tmp_path,
        "broken",
        name="Broken",
        icons=["home"],
        manifest="id: broken\nname: Broken\nicons:\n  - home\n",
    )
    cat = LocalIconSetCatalog(tmp_path)
    with pytest.raises(ProviderError, match="icon set manifest invalid"):
        asyncio.run(cat.sets())
