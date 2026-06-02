#!/usr/bin/env python3
"""Prune unused icon-font families from a built Flutter web bundle.

Why this exists
---------------
Production web builds are made with ``--no-tree-shake-icons`` because Flutter's
icon tree-shaker corrupts the variable-axis (``weight``) data of the
``MaterialSymbolsSharp`` font in release builds, so the admin app's
``Symbols.*_sharp`` icons render in ``flutter run`` (debug, no tree-shaking) but
vanish on the deployed release build. See flutter/flutter#183381 and the
AppManagement CLAUDE.md "Production deployment" section.

The catch: ``--no-tree-shake-icons`` ships *every* font the package declares at
full size, and the ``material_symbols_icons`` package's pubspec declares three
families — Outlined (10 MB) + Rounded (15 MB) + Sharp (8.3 MB). This app uses
only Sharp (zero ``_rounded`` / ``_outlined`` usages), and Flutter web loads
every font listed in ``FontManifest.json`` eagerly at startup, so the two unused
families would add ~25 MB to first load for nothing.

This script deletes those unused families from the *built artifact* after the
Flutter build: it removes their ``.ttf`` files from ``build/web`` and strips
their entries from ``FontManifest.json``. No package fork, no vendored fonts, no
Dart changes — and it matches by family-name substring, so it survives
``material_symbols_icons`` version bumps.

``AssetManifest`` is intentionally left untouched: no code references the removed
families, so a stale asset entry is never fetched (no 404). Fonts are loaded via
``FontManifest.json`` only, which is what we fix here.

Usage
-----
    python3 deploy/prune_web_fonts.py <build_dir> [family_substr ...]

``build_dir`` is the Flutter web output (e.g. ``build/web``). If no family
substrings are given, the defaults below are used. Safe to re-run (idempotent)
and a no-op if the bundle / families are already absent.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# Family-name substrings to drop. The app uses only MaterialSymbolsSharp; the
# Outlined/Rounded families are dead weight under --no-tree-shake-icons.
# CupertinoIcons (~252 KB) is also unused but small, so it is left in place by
# default — pass it explicitly to prune it too.
DEFAULT_DROP = ("MaterialSymbolsRounded", "MaterialSymbolsOutlined")


def prune(build_dir: Path, drop_substrings: tuple[str, ...]) -> int:
    assets_dir = build_dir / "assets"
    manifest_path = assets_dir / "FontManifest.json"

    if not manifest_path.is_file():
        # Non-fatal: a missing manifest means there's nothing to prune (e.g. the
        # bundle was cleaned). Don't fail the build over it.
        print(f"[prune-fonts] no FontManifest at {manifest_path}; nothing to do")
        return 0

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    kept: list[dict] = []
    dropped_families: list[str] = []
    freed_bytes = 0

    for entry in manifest:
        family = entry.get("family", "")
        if any(sub in family for sub in drop_substrings):
            dropped_families.append(family)
            for font in entry.get("fonts", []):
                asset = font.get("asset")
                if not asset:
                    continue
                font_file = assets_dir / asset
                if font_file.is_file():
                    freed_bytes += font_file.stat().st_size
                    font_file.unlink()
                    print(f"[prune-fonts] removed {font_file.relative_to(build_dir)}")
                else:
                    print(f"[prune-fonts] (already absent) {asset}")
        else:
            kept.append(entry)

    if not dropped_families:
        print(f"[prune-fonts] no matching families to prune in {manifest_path}")
        return 0

    # Rewrite the manifest without the dropped families (compact, like Flutter's).
    manifest_path.write_text(json.dumps(kept, separators=(",", ":")), encoding="utf-8")

    freed_mb = freed_bytes / (1024 * 1024)
    print(
        f"[prune-fonts] dropped {len(dropped_families)} families "
        f"({', '.join(dropped_families)}), freed {freed_mb:.1f} MB; "
        f"kept {len(kept)} families"
    )
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        print("error: missing <build_dir> argument", file=sys.stderr)
        return 2

    build_dir = Path(argv[1])
    drop = tuple(argv[2:]) or DEFAULT_DROP

    if not build_dir.is_dir():
        print(f"[prune-fonts] build dir {build_dir} not found; nothing to do")
        return 0

    return prune(build_dir, drop)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
