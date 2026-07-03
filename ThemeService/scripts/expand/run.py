"""Expand an existing run: generate only the slots that aren't done yet.

Reopens an already-produced run directory, treats every slot already
present in its ``output.yaml`` as done (seeds the executor with the saved
outputs), and runs the DAG for only the not-yet-done nodes declared in
that dir's ``app.yaml`` — writing the result back **in place**.

Two use cases:

- **Resume** a run that failed partway: the gaps in ``output.yaml`` (a colour
  node that failed, an image slot that never generated) are filled.
- **Expand** a finished run with new slots. The run dir's ``app.yaml`` is a
  frozen *snapshot*, so to expand against an **updated** inventory pass the
  live one with ``--app-yaml`` (e.g. ``apps/<app_id>/app.yaml``); the run's
  snapshot is then refreshed to match. With no ``--app-yaml`` the snapshot is
  used as-is (the resume case).

Done-ness is YAML presence only — a slot counts as done if it's in
``output.yaml``, regardless of whether its file is on disk. The atomic
nodes (colour/font/text/icon resolve all their slots at once) re-run whole
if any declared slot is missing from their set. The original full-run
``cost`` in ``output.yaml`` is preserved; this pass's spend is appended to
``expansion_cost.yaml``.

Run from the package root (so ``.env`` is found):

    poetry run python scripts/expand/run.py --run-dir apps/<app_id>/<run_id>
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

from schema import ExpansionKind
from src.core.errors import PipelineError
from src.core.run_context import APP_FILENAME, RunContext, load_run
from src.executor.orchestrator import Pipeline
from src.executor.seed import all_slot_ids, build_seed
from src.executor.writer import Writer

RULE = "=" * 72


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="expand",
        description=(
            "Generate only the slots of an existing run that aren't done "
            "yet (seed the done nodes from output.yaml; write back in place)."
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
        "--app-yaml",
        type=Path,
        default=None,
        help="Updated slot inventory to expand against (e.g. the live "
        "apps/<app_id>/app.yaml). Defaults to the run dir's snapshot; when "
        "given, the snapshot is refreshed to match.",
    )
    return parser.parse_args(argv)


async def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    run_dir: Path = args.run_dir.resolve()
    try:
        app, cust, output = load_run(run_dir, app_yaml=args.app_yaml)
    except PipelineError as exc:
        raise SystemExit(str(exc))

    seed = build_seed(app, output)
    to_generate = all_slot_ids(app) - seed.keys()

    print(f"\n{RULE}\nexpand {run_dir}\n{RULE}")
    print(f"done (seeded slots): {sorted(seed)}")
    print(f"to generate (slots): {sorted(to_generate)}")

    if not to_generate:
        print("\nalready complete — nothing to generate (no spend).")
        return 0

    # out_root/<app_id>/<run_id> == run_dir, so out_root is two up. The
    # run_id arg points RunContext at this existing dir instead of minting
    # a fresh timestamped one.
    run_ctx = RunContext(
        app, cust, out_root=run_dir.parent.parent, run_id=run_dir.name
    )

    result = await Pipeline().run(run_ctx, seed=seed)
    Writer().write_expansion(
        result,
        run_ctx,
        original_cost=output.cost,
        original_category=output.category,
        kind=ExpansionKind.EXPAND,
    )
    # Expanded against an updated inventory → refresh the dir's snapshot so its
    # app.yaml matches the slots its output.yaml now has.
    if args.app_yaml is not None:
        Writer._dump_model(run_ctx.app, run_ctx.run_dir / APP_FILENAME)
        print(f"refreshed app.yaml snapshot: {run_ctx.run_dir / APP_FILENAME}")

    cost = Writer._run_cost(result)
    print(f"\n{RULE}\ngenerated: {sorted(result.generated)}")
    print(f"this pass cost: ${cost.total:.6f}")
    print(f"output: {run_ctx.output_path()}")
    print(f"ledger: {run_ctx.expansion_cost_path()}\n{RULE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
