"""Regenerate one or more slots of an existing run, in place, with optional
free-text steering.

Reopens a produced run directory and re-makes just the slot(s) you name —
a colour, font, text, icon, or lottie slot — while keeping everything else
byte-for-byte. Every other node is seeded from the saved ``output.yaml`` and
skipped; the targeted slots' nodes re-run with the prior shown as fixed
context, so an atomic node (colour/font/text/icon) regenerates only the
named slot(s) and preserves its other slots verbatim.

Naming several slots of the same atomic node regenerates them *together* in
one harmonised call — e.g. ``--slot primary --slot accent`` re-rolls both
against the fixed background/text. ``--spec`` is an optional instruction
applied to every named slot ("warmer", "more playful"); omit it to simply
re-roll. The original full-run ``cost`` is preserved; this pass is appended
to ``expansion_cost.yaml`` as a ``regenerate`` entry recording the slots and
their steering.

Images are NOT handled here — they have a create-new-vs-edit choice and a
version history, so they have their own ``scripts/regen_image`` entrypoint.

Run from the package root (so ``.env`` is found):

    poetry run python scripts/regen/run.py \\
        --run-dir apps/<app_id>/<run_id> --slot <slot> [--slot <slot> ...] \\
        [--spec "make it warmer"]
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

from schema import ExpansionKind, OverwriteSpecs
from src.core.errors import PipelineError
from src.core.run_context import RunContext, load_run
from src.executor.orchestrator import Pipeline
from src.executor.seed import all_slot_ids, build_seed
from src.executor.writer import Writer

RULE = "=" * 72


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="regen",
        description=(
            "Regenerate one or more colour/font/text/icon/lottie slots of an "
            "existing run in place, preserving everything else. Images use "
            "regen_image."
        ),
    )
    parser.add_argument(
        "--run-dir",
        required=True,
        type=Path,
        help="Existing run directory (holds app.yaml, customization.yaml, "
        "output.yaml), e.g. apps/combatden/ZenBJJ.",
    )
    parser.add_argument(
        "--slot",
        required=True,
        action="append",
        dest="slots",
        help="A slot id to regenerate. Repeatable; slots of the same atomic "
        "node are regenerated together.",
    )
    parser.add_argument(
        "--spec",
        default="",
        help="Optional free-text steering applied to every named slot "
        "(e.g. 'make it warmer'). Omit to simply re-roll.",
    )
    return parser.parse_args(argv)


async def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    run_dir: Path = args.run_dir.resolve()
    try:
        app, cust, output = load_run(run_dir)
    except PipelineError as exc:
        raise SystemExit(str(exc))

    # Dedupe, preserve order. Images are out of scope (regen_image owns them).
    slots = list(dict.fromkeys(args.slots))
    image_ids = {s.id for s in app.images}
    targetable = all_slot_ids(app) - image_ids
    unknown = [s for s in slots if s not in targetable]
    if unknown:
        raise SystemExit(
            f"cannot regenerate {unknown} here. Choose from "
            f"{sorted(targetable)} (image slots use regen_image)."
        )

    # Seed everything present, then DROP the targets so they're re-made; the
    # seed is the sole control of what regenerates. The single steering string
    # is stamped on whatever is re-made.
    seed = build_seed(app, output)
    for slot in slots:
        seed.pop(slot, None)
    overwrite_specs = OverwriteSpecs(specs=args.spec)

    print(f"\n{RULE}\nregenerate {sorted(slots)} in {run_dir}\n{RULE}")
    if args.spec:
        print(f"steering: {args.spec!r}")

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
    print(f"\n{RULE}\nregenerated nodes: {sorted(result.generated)}")
    print(f"this pass cost: ${cost.total:.6f}")
    print(f"output: {run_ctx.output_path()}")
    print(f"ledger: {run_ctx.expansion_cost_path()}\n{RULE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
