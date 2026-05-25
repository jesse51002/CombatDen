"""Regenerate ONE image slot of an existing run, in place.

Images get their own entrypoint (not the generic ``regen``) because they
have a mode the other slots don't: ``--mode``

- ``create_new`` (default) — generate a fresh image from an augmented prompt,
  the way a full run does, optionally steered by ``--spec``.
- ``edit_current_image`` — image-to-image: edit the slot's *current* image,
  changing only what ``--spec`` asks and keeping the rest. Backed by the
  provider's edit endpoint.

The slot is dropped from the seed so it (and only it) regenerates; every
other slot is preserved verbatim. There is no version history in
``output.yaml`` — instead the prior image is kept as a numbered file in the
run's ``images/`` dir (``<slot>.v1.png``, ``.v2.png`` …) so nothing is lost.
The original ``output.yaml`` ``cost`` is preserved; this pass is appended to
``expansion_cost.yaml`` as a ``regenerate`` entry.

Run from the package root (so ``.env`` is found):

    poetry run python scripts/regen_image/run.py \\
        --run-dir apps/<app_id>/<run_id> --slot <image_id> \\
        [--spec "darker background"] [--mode edit_current_image]
"""

from __future__ import annotations

import argparse
import asyncio
import shutil
import sys
from pathlib import Path

# Standalone entrypoint two levels under the repo root: make `src`/`schema`
# importable regardless of how the venv installed them.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from schema import ExpansionKind, ImageToImage, OverwriteSpecs
from src.core.errors import PipelineError
from src.core.run_context import (
    FINAL_IMAGES_DIRNAME,
    IMAGES_DIRNAME,
    RunContext,
    load_run,
)
from src.executor.orchestrator import Pipeline
from src.executor.seed import build_seed
from src.executor.writer import Writer

RULE = "=" * 72
CREATE_NEW = "create_new"
EDIT_CURRENT = "edit_current_image"
IMAGE_SUFFIX = ".png"


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="regen_image",
        description=(
            "Regenerate one image slot of an existing run in place — create a "
            "fresh image or edit the current one (image-to-image)."
        ),
    )
    parser.add_argument(
        "--run-dir",
        required=True,
        type=Path,
        help="Existing run directory, e.g. apps/combatden/ZenBJJ.",
    )
    parser.add_argument(
        "--slot", required=True, help="Image slot id to regenerate."
    )
    parser.add_argument(
        "--spec",
        default="",
        help="Steering: the change to make (edit) or extra direction (new).",
    )
    parser.add_argument(
        "--mode",
        choices=[CREATE_NEW, EDIT_CURRENT],
        default=CREATE_NEW,
        help="create_new (fresh image) or edit_current_image (image-to-image).",
    )
    return parser.parse_args(argv)


def _preserve_prior(run_dir: Path, slot: str) -> Path | None:
    """Copy the slot's current final image to the next numbered file in
    ``images/`` so the prior version is never lost. Returns the archive path
    (or ``None`` when there's no current image to preserve)."""
    current = run_dir / FINAL_IMAGES_DIRNAME / f"{slot}{IMAGE_SUFFIX}"
    if not current.is_file():
        return None
    images_dir = run_dir / IMAGES_DIRNAME
    images_dir.mkdir(parents=True, exist_ok=True)
    n = 1
    while (images_dir / f"{slot}.v{n}{IMAGE_SUFFIX}").exists():
        n += 1
    archive = images_dir / f"{slot}.v{n}{IMAGE_SUFFIX}"
    shutil.copy2(current, archive)
    return archive


async def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    run_dir: Path = args.run_dir.resolve()
    try:
        app, cust, output = load_run(run_dir)
    except PipelineError as exc:
        raise SystemExit(str(exc))

    if args.slot not in {s.id for s in app.images}:
        ids = ", ".join(s.id for s in app.images)
        raise SystemExit(
            f"no image slot {args.slot!r}; available: {ids}"
        )
    if args.mode == EDIT_CURRENT and not (
        run_dir / FINAL_IMAGES_DIRNAME / f"{args.slot}{IMAGE_SUFFIX}"
    ).is_file():
        raise SystemExit(
            f"--mode {EDIT_CURRENT} needs an existing image for "
            f"{args.slot!r}; none found. Use {CREATE_NEW}."
        )

    # Keep the prior image (numbered) before it's overwritten.
    archive = _preserve_prior(run_dir, args.slot)

    seed = build_seed(app, output)
    seed.pop(args.slot, None)  # drop the target so it (only) regenerates
    overwrite_specs = OverwriteSpecs(
        specs=args.spec,
        image_to_image=ImageToImage() if args.mode == EDIT_CURRENT else None,
    )

    print(f"\n{RULE}\nregen_image {args.slot} ({args.mode}) in {run_dir}")
    if args.spec:
        print(f"steering: {args.spec!r}")
    if archive is not None:
        print(f"prior kept: {archive}")
    print(RULE)

    run_ctx = RunContext(
        app, cust, out_root=run_dir.parent.parent, run_id=run_dir.name
    )
    result = await Pipeline().run(
        run_ctx, seed=seed, overwrite_specs=overwrite_specs
    )
    Writer().write_expansion(
        result,
        run_ctx,
        original_cost=output.cost,
        kind=ExpansionKind.REGENERATE,
        overwrite_specs=overwrite_specs,
    )

    cost = Writer._run_cost(result)
    print(f"\n{RULE}\nregenerated: {sorted(result.generated)}")
    print(f"this pass cost: ${cost.total:.6f}")
    print(f"output: {run_ctx.output_path()}\n{RULE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
