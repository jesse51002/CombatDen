"""Regenerate one or more image slots of an existing run, in place.

Images get their own entrypoint (not the generic ``regen``) because they
have a mode the other slots don't: ``--mode``

- ``create_new`` (default) — generate a fresh image from an augmented prompt,
  the way a full run does, optionally steered by ``--spec``.
- ``edit_current_image`` — image-to-image: edit the slot's *current* image,
  changing only what ``--spec`` asks and keeping the rest. Backed by the
  provider's edit endpoint.

``--slot`` is repeatable: every named slot is dropped from the seed so it (and
only it) regenerates, in one pass, while every other slot is preserved
verbatim. ``--spec`` / ``--mode`` apply to all named slots. There is no version
history in ``output.yaml`` — instead each slot's prior image is kept as a
numbered file in the run's ``images/`` dir (``<slot>.v1.png``, ``.v2.png`` …)
so nothing is lost. The original ``output.yaml`` ``cost`` is preserved; this
pass is appended to ``expansion_cost.yaml`` as a ``regenerate`` entry.

Run from the package root (so ``.env`` is found):

    poetry run python scripts/regen_image/run.py \\
        --run-dir apps/<app_id>/<run_id> --slot <image_id> [--slot <image_id> ...] \\
        [--spec "darker background"] [--mode edit_current_image] \\
        [--app-yaml apps/<app_id>/app.yaml]

The run dir's ``app.yaml`` is a frozen *snapshot*. To re-roll a slot against
an **updated** manifest (e.g. an edited slot description in the live
``apps/<app_id>/app.yaml``), pass it with ``--app-yaml``; the snapshot is then
refreshed to match. Without it the snapshot is used as-is.
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
    APP_FILENAME,
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
            "Regenerate one or more image slots of an existing run in place — "
            "create fresh images or edit the current ones (image-to-image)."
        ),
    )
    parser.add_argument(
        "--run-dir",
        required=True,
        type=Path,
        help="Existing run directory, e.g. apps/combatden/ZenBJJ.",
    )
    parser.add_argument(
        "--slot",
        required=True,
        action="append",
        dest="slots",
        help="An image slot id to regenerate. Repeatable; all named slots "
        "regenerate in one pass.",
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
    parser.add_argument(
        "--app-yaml",
        type=Path,
        default=None,
        help="Updated manifest to re-roll against (e.g. the live "
        "apps/<app_id>/app.yaml). Defaults to the run dir's snapshot; when "
        "given, the snapshot is refreshed to match.",
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
        app, cust, output = load_run(run_dir, app_yaml=args.app_yaml)
    except PipelineError as exc:
        raise SystemExit(str(exc))

    # Dedupe, preserve order. Every named slot must be an image slot.
    slots = list(dict.fromkeys(args.slots))
    image_ids = {s.id for s in app.images}
    unknown = [s for s in slots if s not in image_ids]
    if unknown:
        ids = ", ".join(sorted(image_ids))
        raise SystemExit(f"no image slot(s) {unknown}; available: {ids}")
    if args.mode == EDIT_CURRENT:
        missing = [
            s
            for s in slots
            if not (
                run_dir / FINAL_IMAGES_DIRNAME / f"{s}{IMAGE_SUFFIX}"
            ).is_file()
        ]
        if missing:
            raise SystemExit(
                f"--mode {EDIT_CURRENT} needs an existing image for each slot; "
                f"none found for {missing}. Use {CREATE_NEW}."
            )

    # Keep each slot's prior image (numbered) before it's overwritten.
    archives = {s: _preserve_prior(run_dir, s) for s in slots}

    seed = build_seed(app, output)
    for slot in slots:
        seed.pop(slot, None)  # drop the targets so they (only) regenerate
    overwrite_specs = OverwriteSpecs(
        specs=args.spec,
        image_to_image=ImageToImage() if args.mode == EDIT_CURRENT else None,
    )

    print(f"\n{RULE}\nregen_image {sorted(slots)} ({args.mode}) in {run_dir}")
    if args.spec:
        print(f"steering: {args.spec!r}")
    for archive in archives.values():
        if archive is not None:
            print(f"prior kept: {archive}")
    print(RULE)

    run_ctx = RunContext(
        app,
        cust,
        out_root=run_dir.parent.parent,
        run_id=run_dir.name,
        overwrite_specs=overwrite_specs,
    )
    result = await Pipeline().run(run_ctx, seed=seed)
    Writer().write_expansion(
        result,
        run_ctx,
        original_cost=output.cost,
        kind=ExpansionKind.REGENERATE,
    )
    # Re-rolled against an updated manifest → refresh the dir's snapshot so its
    # app.yaml matches what the slot was regenerated from.
    if args.app_yaml is not None:
        Writer._dump_model(run_ctx.app, run_ctx.run_dir / APP_FILENAME)
        print(f"refreshed app.yaml snapshot: {run_ctx.run_dir / APP_FILENAME}")

    cost = Writer._run_cost(result)
    print(f"\n{RULE}\nregenerated: {sorted(result.generated)}")
    print(f"this pass cost: ${cost.total:.6f}")
    print(f"output: {run_ctx.output_path()}\n{RULE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
