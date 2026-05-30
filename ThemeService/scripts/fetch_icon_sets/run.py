#!/usr/bin/env python
"""Build the local icon-set catalog under ``assets/icon_sets/``.

Each entry in ``SETS`` is one curated icon set, sourced from a pinned npm
package (raw SVGs or an ``@iconify-json/*`` ``icons.json``). For every set the
script downloads the package, writes ``assets/icon_sets/<id>/icons/<name>.svg``
for each icon it keeps, normalizes hardcoded black to ``currentColor`` so the
app can tint per theme, and emits a ``set.yaml`` manifest matching
``IconSetCatalogEntry`` (id, name, vibe, icons) plus provenance keys
(license/source/attribution) the catalog ignores.

The roster is deliberately one set per *distinct visual character* — not
multiple weight/fill variants of one library. Run with::

    poetry run python scripts/fetch_icon_sets/run.py            # all sets
    poetry run python scripts/fetch_icon_sets/run.py lucide solar_bold_duotone

Rebuilds are idempotent: each ``assets/icon_sets/<id>/`` is wiped and rebuilt
from its pinned source. Downloaded tarballs (npm and GitHub) are cached under
``.cache/``.

Sources come in three kinds: ``npm_dir`` (copy SVGs from an npm tarball),
``github`` (copy SVGs from a pinned GitHub repo tarball — used for ``doodle``,
whose icons aren't published to npm) and ``iconify`` (render SVGs from an
``@iconify-json/*`` ``icons.json``).
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from dataclasses import dataclass
from pathlib import Path

import yaml

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
ASSETS_DIR = REPO_ROOT / "assets" / "icon_sets"
CACHE_DIR = SCRIPT_DIR / ".cache"
GITHUB_TARBALL = "https://codeload.github.com/{repo}/tar.gz/{ref}"

# npm_dir: copy SVG files straight from a subdir of an unpacked npm tarball.
# github: copy SVG files from a subdir of a pinned GitHub repo tarball.
# iconify: render SVGs from an ``@iconify-json/*`` ``icons.json``.
KIND_NPM_DIR = "npm_dir"
KIND_GITHUB = "github"
KIND_ICONIFY = "iconify"

# Hardcoded pure-black fills/strokes some libraries ship; rewrite to
# currentColor so the consuming app tints them per theme. Anything already
# currentColor / none / a real colour is left untouched.
_HARDCODED_BLACK = re.compile(
    r'(fill|stroke)\s*=\s*"(?:#000(?:000)?|black)"', re.IGNORECASE
)
_SVG_HEADER = '<svg xmlns="http://www.w3.org/2000/svg"'


@dataclass(frozen=True)
class IconSet:
    """One curated icon set: where to fetch it and how to name its icons."""

    id: str
    name: str
    vibe: str
    license: str
    source: str
    kind: str
    npm: str = ""  # "pkg@version" for npm_dir / iconify
    github: str = ""  # "owner/repo@ref" for github (ref pinned to a commit SHA)
    # npm_dir / github tuning:
    svg_subdir: str = ""  # path inside the tarball, e.g. "package/24/solid"
    recursive: bool = False  # recurse into svg_subdir (github category folders)
    strip_suffix: str = ""  # drop this from each filename, e.g. "-bold"
    skip_contains: str = ""  # skip files whose name contains this, e.g. "-sharp"
    # iconify tuning:
    keep_suffix: str = ""  # only keep icons ending here; also stripped from name
    # CC-BY sets only:
    attribution: str | None = None

    def build(self) -> None:
        """(Re)build ``assets/icon_sets/<id>/`` from this set's source."""
        dst = ASSETS_DIR / self.id
        icons_dst = dst / "icons"
        if dst.exists():
            shutil.rmtree(dst)
        icons_dst.mkdir(parents=True)

        if self.kind == KIND_NPM_DIR:
            names = self._emit_svg_dir(icons_dst, _ensure_package(self.npm))
        elif self.kind == KIND_GITHUB:
            names = self._emit_svg_dir(icons_dst, _ensure_github(self.github))
        elif self.kind == KIND_ICONIFY:
            names = self._emit_iconify(icons_dst)
        else:
            raise ValueError(f"unknown source kind {self.kind!r}")

        if not names:
            shutil.rmtree(dst)
            raise RuntimeError(f"{self.id}: produced no icons — source layout changed?")

        self._write_manifest(dst, names)
        print(f"  {self.id}: {len(names)} icons -> {dst.relative_to(REPO_ROOT)}")

    def _emit_svg_dir(self, icons_dst: Path, root: Path) -> list[str]:
        """Copy SVGs from ``root/svg_subdir`` (the npm_dir / github path).

        Recurses into category folders when ``recursive`` is set, and dedupes
        on the cleaned name (a stem that appears in two folders is kept once,
        first by sort order) so flattening can't overwrite or double-count.
        """
        src = root / self.svg_subdir
        if not src.is_dir():
            raise RuntimeError(f"{self.id}: missing {self.svg_subdir} under source")
        globber = src.rglob if self.recursive else src.glob
        names: list[str] = []
        seen: set[str] = set()
        for svg in sorted(globber("*.svg")):
            stem = svg.stem
            if self.skip_contains and self.skip_contains in stem:
                continue
            name = self._clean_name(stem)
            if name in seen:
                continue
            seen.add(name)
            (icons_dst / f"{name}.svg").write_text(
                _normalize_svg(svg.read_text(encoding="utf-8")), encoding="utf-8"
            )
            names.append(name)
        return names

    def _emit_iconify(self, icons_dst: Path) -> list[str]:
        root = _ensure_package(self.npm)
        data = json.loads((root / "package" / "icons.json").read_text("utf-8"))
        def_w, def_h = data.get("width", 24), data.get("height", 24)
        names: list[str] = []
        for raw_name, entry in data["icons"].items():
            if self.keep_suffix and not raw_name.endswith(self.keep_suffix):
                continue
            name = self._clean_name(raw_name)
            svg = _render_iconify(entry, def_w, def_h)
            (icons_dst / f"{name}.svg").write_text(svg, encoding="utf-8")
            names.append(name)
        return names

    def _clean_name(self, stem: str) -> str:
        """Normalize one source filename to a catalog icon short-name."""
        if self.strip_suffix and stem.endswith(self.strip_suffix):
            stem = stem[: -len(self.strip_suffix)]
        if self.keep_suffix and stem.endswith(self.keep_suffix):
            stem = stem[: -len(self.keep_suffix)]
        return stem.strip().lower().replace(" ", "-").replace("_", "-")

    def _write_manifest(self, dst: Path, names: list[str]) -> None:
        manifest: dict[str, object] = {
            "id": self.id,
            "name": self.name,
            "license": self.license,
            "source": self.source,
        }
        if self.attribution:
            manifest["attribution"] = self.attribution
        manifest["vibe"] = self.vibe.strip()
        manifest["icons"] = sorted(names)
        (dst / "set.yaml").write_text(
            yaml.safe_dump(manifest, sort_keys=False, allow_unicode=True, width=88),
            encoding="utf-8",
        )


_PACKAGE_CACHE: dict[str, Path] = {}


def _ensure_package(npm_spec: str) -> Path:
    """Download (once) and unpack an npm package; return its extraction dir."""
    if npm_spec in _PACKAGE_CACHE:
        return _PACKAGE_CACHE[npm_spec]
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    out = subprocess.run(
        ["npm", "pack", npm_spec, "--pack-destination", str(CACHE_DIR)],
        check=True,
        capture_output=True,
        text=True,
    )
    tarball = CACHE_DIR / out.stdout.strip().splitlines()[-1].strip()
    extract_dir = Path(tempfile.mkdtemp(prefix="iconset-"))
    with tarfile.open(tarball) as tf:
        tf.extractall(extract_dir, filter="data")
    _PACKAGE_CACHE[npm_spec] = extract_dir
    return extract_dir


def _ensure_github(spec: str) -> Path:
    """Download (once) a pinned GitHub repo tarball; return its top dir.

    ``spec`` is ``owner/repo@ref`` — pin ``ref`` to a commit SHA so rebuilds
    are deterministic. codeload tarballs unpack to a single ``repo-ref/`` dir,
    which is returned so ``svg_subdir`` resolves against the repo root.
    """
    if spec in _PACKAGE_CACHE:
        return _PACKAGE_CACHE[spec]
    repo, _, ref = spec.partition("@")
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    tarball = CACHE_DIR / f"{repo.replace('/', '-')}-{ref}.tar.gz"
    if not tarball.exists():
        subprocess.run(
            ["curl", "-sL", "-o", str(tarball),
             GITHUB_TARBALL.format(repo=repo, ref=ref)],
            check=True,
        )
    extract_dir = Path(tempfile.mkdtemp(prefix="iconset-gh-"))
    with tarfile.open(tarball) as tf:
        tf.extractall(extract_dir, filter="data")
    top = next(p for p in extract_dir.iterdir() if p.is_dir())
    _PACKAGE_CACHE[spec] = top
    return top


def _normalize_svg(text: str) -> str:
    """Rewrite hardcoded black fills/strokes to currentColor.

    Skips any SVG containing a ``<mask>`` — there ``#000``/``#fff`` are
    luminance values (hide/show), not colours, and rewriting them corrupts
    the mask. All current sources already ship currentColor, so this is a
    defensive net for flat icons, not a transform anything here relies on.
    """
    if "<mask" in text:
        return text
    return _HARDCODED_BLACK.sub(lambda m: f'{m.group(1)}="currentColor"', text)


def _render_iconify(entry: dict, default_w: int, default_h: int) -> str:
    """Wrap one Iconify icon body into a standalone currentColor SVG."""
    w = entry.get("width", default_w)
    h = entry.get("height", default_h)
    left, top = entry.get("left", 0), entry.get("top", 0)
    return (
        f'{_SVG_HEADER} width="{w}" height="{h}" '
        f'viewBox="{left} {top} {w} {h}" fill="currentColor">'
        f'{entry["body"]}</svg>'
    )


SETS: list[IconSet] = [
    IconSet(
        id="lucide",
        name="Lucide",
        license="ISC",
        source="https://github.com/lucide-icons/lucide",
        kind=KIND_NPM_DIR,
        npm="lucide-static@1.16.0",
        svg_subdir="package/icons",
        vibe=(
            "A clean, modern line-icon family: even 2px strokes, rounded caps "
            "and joins, generous open shapes, friendly-but-neutral geometry. "
            "Monochrome currentColor throughout. Reads crisp, contemporary and "
            "unobtrusive — at home in utility UI, navigation and settings. The "
            "safe default when a brand wants tidy, legible icons with no strong "
            "personality of their own."
        ),
    ),
    IconSet(
        id="heroicons_solid",
        name="Heroicons Solid",
        license="MIT",
        source="https://github.com/tailwindlabs/heroicons",
        kind=KIND_NPM_DIR,
        npm="heroicons@2.2.0",
        svg_subdir="package/24/solid",
        vibe=(
            "Bold, confident filled glyphs from the makers of Tailwind. Solid "
            "shapes with smooth, slightly rounded corners and strong silhouettes "
            "that stay legible at small sizes. High visual weight and contrast — "
            "fits assertive, energetic, strength- and combat-oriented brands that "
            "want icons to feel substantial rather than delicate."
        ),
    ),
    IconSet(
        id="phosphor_bold",
        name="Phosphor Bold",
        license="MIT",
        source="https://github.com/phosphor-icons/core",
        kind=KIND_NPM_DIR,
        npm="@phosphor-icons/core@2.1.1",
        svg_subdir="package/assets/bold",
        strip_suffix="-bold",
        vibe=(
            "Thick, heavy strokes with rounded ends — chunky and punchy. The "
            "weight gives every icon a sturdy, athletic, high-impact feel without "
            "tipping into fully filled shapes. Aggressive and sporty; suits gyms, "
            "performance and action brands that want icons to hit hard while "
            "staying friendly and rounded rather than sharp."
        ),
    ),
    IconSet(
        id="phosphor_duotone",
        name="Phosphor Duotone",
        license="MIT",
        source="https://github.com/phosphor-icons/core",
        kind=KIND_NPM_DIR,
        npm="@phosphor-icons/core@2.1.1",
        svg_subdir="package/assets/duotone",
        strip_suffix="-duotone",
        vibe=(
            "Line icons with a soft two-tone treatment: a crisp foreground stroke "
            "over a low-opacity currentColor fill, so each icon reads as two "
            "shades of the same theme colour. Playful, modern and a little "
            "premium without using a second hue. Good for friendly, contemporary "
            "lifestyle and wellness brands wanting depth beyond a flat line."
        ),
    ),
    IconSet(
        id="mingcute",
        name="MingCute",
        license="Apache-2.0",
        source="https://github.com/mingcute-design/mingcute-icons",
        kind=KIND_ICONIFY,
        npm="@iconify-json/mingcute@1.2.7",
        keep_suffix="-line",
        vibe=(
            "Soft, characterful line icons on a tidy 24px grid: rounded corners, "
            "gentle curves and a touch of warmth and whimsy that the more neutral "
            "line sets lack. Friendly and approachable without being childish. "
            "Fits community-minded, welcoming, lifestyle and boutique brands that "
            "want a little personality in their iconography."
        ),
    ),
    IconSet(
        id="pixelarticons",
        name="Pixelart Icons",
        license="MIT",
        source="https://github.com/halfmage/pixelarticons",
        kind=KIND_NPM_DIR,
        npm="pixelarticons@2.1.1",
        svg_subdir="package/svg",
        skip_contains="-sharp",
        vibe=(
            "Retro 8-bit pixel-art icons drawn on a coarse grid — blocky, "
            "nostalgic and unmistakably game-flavoured. A deliberate novelty look "
            "with strong character. Perfect for playful, gamified, esports or "
            "youth-oriented brands; a bold, intentional choice rather than a "
            "neutral default."
        ),
    ),
    IconSet(
        id="solar_bold_duotone",
        name="Solar Bold Duotone",
        license="CC-BY-4.0",
        source="https://github.com/480-Design/Solar-Icon-Set",
        attribution="Solar Icon Set by 480 Design (CC BY 4.0) — https://creativecommons.org/licenses/by/4.0/",
        kind=KIND_ICONIFY,
        npm="@iconify-json/solar@1.2.5",
        keep_suffix="-bold-duotone",
        vibe=(
            "Premium, polished solid icons with heavy corner smoothing and a "
            "two-tone duotone treatment: a bold filled foreground over a soft "
            "low-opacity backing shape, all in one theme colour. Feels refined, "
            "app-store-ready and slightly upscale. Distinct from line-based "
            "duotone by its weight and roundness — suits sleek, modern, premium "
            "fitness and lifestyle brands."
        ),
    ),
    IconSet(
        id="basil",
        name="Basil",
        license="CC-BY-4.0",
        source="https://www.figma.com/community/file/931906394678748246",
        attribution="Basil Icon Set (CC BY 4.0) — https://creativecommons.org/licenses/by/4.0/",
        kind=KIND_ICONIFY,
        npm="@iconify-json/basil@1.2.4",
        keep_suffix="-outline",
        vibe=(
            "Flat, slightly playful outline icons with a distinctive hand-tuned "
            "feel: relaxed proportions, soft corners and a friendly, informal "
            "personality that sets them apart from strictly geometric line sets. "
            "A characterful system set for casual, approachable, community-led "
            "brands that still want consistent, legible UI icons."
        ),
    ),
    IconSet(
        id="doodle",
        name="Doodle Icons",
        license="Free for commercial use, no attribution",
        # Khushmeen's doodle icons (free, no attribution); fetched as raw SVGs
        # from this MIT-licensed React wrapper repo, pinned to a commit.
        source="https://khushmeen.com/icons.html",
        kind=KIND_GITHUB,
        github="svatsa159/react-doodle-icons@b51da0371e992b5d03e768fd1f570e8e9500c617",
        svg_subdir="src/icons",
        recursive=True,
        vibe=(
            "Hand-drawn doodle icons: loose, sketchy strokes with a warm, human, "
            "imperfect quality that no geometric set can fake. Personality-forward "
            "and informal. Ideal for creative, indie, kids', craft or "
            "community-driven brands wanting an approachable, handmade feel — a "
            "strong stylistic statement, not a neutral default."
        ),
    ),
]


def main(argv: list[str]) -> int:
    wanted = set(argv) if argv else None
    sets = [s for s in SETS if wanted is None or s.id in wanted]
    if wanted:
        unknown = wanted - {s.id for s in SETS}
        if unknown:
            print(f"unknown set id(s): {', '.join(sorted(unknown))}", file=sys.stderr)
            return 2
    ASSETS_DIR.mkdir(parents=True, exist_ok=True)
    print(f"Building {len(sets)} icon set(s) into {ASSETS_DIR.relative_to(REPO_ROOT)}/")
    for icon_set in sets:
        icon_set.build()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
