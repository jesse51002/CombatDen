"""Redo *only* the background removal for image slot(s) of an existing run.

Unlike ``regen_image`` (which re-*generates* the image — a paid image-gen
call — then removes its background), this calls the background module
directly: it reads each slot's already-generated raw on its solid backdrop,
re-runs remove → crop, and overwrites the deliverable. No image is generated,
no LLM is called, and nothing about the run's brief or manifest is loaded — it
is **legit just the slot and the dir**:

- input  : ``<run-dir>/images/<slot>.raw.png``  (the solid-background raw)
- output : ``<run-dir>/final_images/<slot>.png``  (hard overwrite, no backup)

So there is no ``--app-yaml`` / ``--customization`` / seed / Pipeline / Writer
here — none of the run scaffolding the other scripts need. It composes the same
``BackgroundService`` the image node uses, against the same Recraft remover.

Each slot is one paid Recraft ``removeBackground`` call (~$0.01). Slots are
processed **strictly one at a time** (the provider is rate-limited — never fan
out). The prior ``final_images/<slot>.png`` is **overwritten with no backup**.

Run from the package root (so ``.env`` is found):

    poetry run python scripts/remove_bg/run.py \\
        --run-dir apps/<app_id>/<run_id> \\
        --slot <image_id> [--slot <image_id> ...]
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

# Standalone entrypoint two levels under the repo root: make `src`/`schema`
# importable regardless of how the venv installed them.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from src.core.run_context import FINAL_IMAGES_DIRNAME, IMAGES_DIRNAME
from src.modules.images.background_service import BackgroundService
from src.shared.services.background_remover import RecraftBackgroundRemover

RULE = "=" * 72
# The raw the image node writes for a slot, and the deliverable's extension.
# Source of truth: ``image_node.RAW_SUFFIX`` — duplicated here so this thin
# script doesn't import the whole image-generation stack just for a constant.
RAW_SUFFIX = ".raw.png"
IMAGE_SUFFIX = ".png"


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="remove_bg",
        description=(
            "Redo only the background removal for image slot(s) of an "
            "existing run: read images/<slot>.raw.png, re-run remove+crop, "
            "and overwrite final_images/<slot>.png. No image generation."
        ),
    )
    parser.add_argument(
        "--run-dir",
        required=True,
        type=Path,
        help="Existing run directory, e.g. apps/combatden/ApexMMA.",
    )
    parser.add_argument(
        "--slot",
        required=True,
        action="append",
        dest="slots",
        help="An image slot id to re-remove the background for. Repeatable; "
        "all named slots are processed sequentially in one invocation.",
    )
    return parser.parse_args(argv)


def _available_raw_stems(images_dir: Path) -> list[str]:
    """Slot ids that have a raw in ``images_dir`` (for a helpful error)."""
    if not images_dir.is_dir():
        return []
    return sorted(
        p.name[: -len(RAW_SUFFIX)]
        for p in images_dir.glob(f"*{RAW_SUFFIX}")
    )


async def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    run_dir: Path = args.run_dir.resolve()
    images_dir = run_dir / IMAGES_DIRNAME
    final_dir = run_dir / FINAL_IMAGES_DIRNAME

    # Pre-flight every slot before spending a cent: a typo'd id should fail
    # loudly listing what raws actually exist, not silently do nothing.
    jobs: list[tuple[str, Path, Path]] = []
    missing: list[str] = []
    for slot in args.slots:
        raw = images_dir / f"{slot}{RAW_SUFFIX}"
        dest = final_dir / f"{slot}{IMAGE_SUFFIX}"
        if raw.is_file():
            jobs.append((slot, raw, dest))
        else:
            missing.append(slot)

    if missing:
        print(RULE)
        print(f"no raw image found for: {', '.join(missing)}")
        print(f"  looked in: {images_dir}")
        available = _available_raw_stems(images_dir)
        if available:
            print(f"  slots with a raw: {', '.join(available)}")
        else:
            print("  (no *.raw.png files here — is the run dir right?)")
        print(RULE)
        return 1

    remover = RecraftBackgroundRemover()
    service = BackgroundService(bg_remover=remover)

    print(RULE)
    print(f"remove_bg — {len(jobs)} slot(s) in {run_dir}")
    print(RULE)

    # Sequential on purpose: Recraft is rate-limited, never fan out.
    fell_back: list[str] = []
    for slot, raw, dest in jobs:
        was_cutout = await service.run(raw, dest)
        if was_cutout:
            print(f"  [ok]       {slot}: {dest}")
        else:
            fell_back.append(slot)
            print(
                f"  [FALLBACK] {slot}: remover never produced a cutout — "
                f"kept the un-removed raw at {dest}"
            )

    print(RULE)
    print(f"spend: ${remover.cost:.4f} (Recraft removeBackground)")
    print(f"output: {final_dir}")
    if fell_back:
        print(f"WARNING: still has a background: {', '.join(fell_back)}")
    print(RULE)
    return 1 if fell_back else 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
