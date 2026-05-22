"""Regenerate ONE image slot of an existing run, in place.

Drives a single ``ImageNode`` against an already-completed run directory:
re-writes that slot's prompt under the *current* ``image_prompt_rule.md``,
re-classifies complexity, regenerates the image, runs background
removal/crop, and writes the new files over the old ones. Then it updates
only that slot's ``prompt`` + ``complexity`` in the run's ``output.yaml``,
re-dumped with the Writer's exact YAML settings so the rest of the file
(every other slot, the palette, the stale ``path`` strings, the cost
block) stays byte-for-byte stable.

Scope is deliberately one image (the pipeline's atomic unit): it reuses
the palette already saved in ``output.yaml`` and never re-runs colours,
fonts, or text. Declared ``depends_on`` images are loaded from
``output.yaml`` and folded into the prompt as style reference, exactly as
a full run would. So a colour-direction change in ``customization.yaml``
will NOT be reflected here (the saved palette is reused); only the prompt
side — driven by ``design_direction`` and the slot description — picks up
edits. For a colour change, re-run the full pipeline.

Run from the package root (so ``.env`` is found):

    poetry run python scripts/regen_one/run.py \
        --run-dir apps/<app_id>/<run_id> --slot <slot_id>
"""

from __future__ import annotations

import argparse
import asyncio
import shutil
import sys
from pathlib import Path

import yaml

# Standalone entrypoint two levels under the repo root: make `src`/`schema`
# importable regardless of how the venv installed them.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from schema import AppFormat, ColorPalette, Customization, ImageOutput
from src.core.run_context import (
    FINAL_IMAGES_DIRNAME,
    IMAGES_DIRNAME,
    OUTPUT_FILENAME,
    RunContext,
)
from src.core.util import load_yaml
from src.modules.base import DependencyKind
from src.modules.images.background_service import BackgroundService
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_node import ImageNode
from src.shared.services.background_remover import PhotoRoomBackgroundRemover
from src.shared.services.litellm_image_generator import LiteLLMImageGenerator
from src.shared.services.llm_client import LiteLLMClient

APP_FILENAME = "app.yaml"
CUSTOMIZATION_FILENAME = "customization.yaml"
RULE = "=" * 72


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="regen_one",
        description=(
            "Regenerate one image slot of an existing run in place "
            "(reuses the saved palette; does not re-run colours)."
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
        help="Image slot id to regenerate (e.g. celebration_image).",
    )
    return parser.parse_args(argv)


def _redirect_run_context(
    app: AppFormat, cust: Customization, run_dir: Path
) -> RunContext:
    """Build a RunContext pointed at an *existing* run dir.

    ``RunContext`` always mints a fresh timestamped run dir on construction;
    we redirect its paths at ``run_dir`` so the node overwrites in place,
    then delete the empty timestamp dir it created.
    """
    run_ctx = RunContext(app, cust, _REPO_ROOT / "apps")
    stray = run_ctx.run_dir
    run_ctx.run_id = run_dir.name
    run_ctx.run_dir = run_dir
    run_ctx.image_dir = run_dir / IMAGES_DIRNAME
    run_ctx.final_image_dir = run_dir / FINAL_IMAGES_DIRNAME
    if stray.exists() and stray.resolve() != run_dir.resolve():
        shutil.rmtree(stray)
    return run_ctx


async def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    run_dir: Path = args.run_dir.resolve()
    slot_id: str = args.slot

    for name in (APP_FILENAME, CUSTOMIZATION_FILENAME, OUTPUT_FILENAME):
        if not (run_dir / name).is_file():
            raise SystemExit(f"missing {name} in {run_dir}")

    app = AppFormat.model_validate(load_yaml(run_dir / APP_FILENAME))
    cust = Customization.model_validate(
        load_yaml(run_dir / CUSTOMIZATION_FILENAME)
    )
    output_data = load_yaml(run_dir / OUTPUT_FILENAME)

    slot = next((s for s in app.images if s.id == slot_id), None)
    if slot is None:
        ids = ", ".join(s.id for s in app.images)
        raise SystemExit(f"no image slot {slot_id!r}; available: {ids}")

    images = output_data.get("image_set", {}).get("images", {})
    if slot_id not in images:
        raise SystemExit(
            f"{slot_id!r} not in {OUTPUT_FILENAME} image_set "
            "(nothing to write back over)"
        )
    old_prompt = images[slot_id].get("prompt", "")

    # Reuse the palette the original run already resolved; we are not
    # re-running colours. Declared image dependencies come from the same
    # output.yaml and are folded into the prompt as reference.
    palette = ColorPalette.model_validate(output_data["color_set"])
    inputs: dict[str, object] = {DependencyKind.COLOR.value: palette}
    for dep_id in slot.depends_on:
        if dep_id not in images:
            raise SystemExit(
                f"{slot_id!r} depends on {dep_id!r}, which is not in "
                f"{OUTPUT_FILENAME} (run the full pipeline first)"
            )
        inputs[dep_id] = ImageOutput.model_validate(images[dep_id])

    run_ctx = _redirect_run_context(app, cust, run_dir)

    llm = LiteLLMClient()
    node = ImageNode(
        run_ctx,
        slot=slot,
        deps=frozenset({DependencyKind.COLOR.value})
        | frozenset(slot.depends_on),
        llm=llm,
        image_gen=LiteLLMImageGenerator(),
        classifier=ComplexityClassifier(llm=llm),
        background=BackgroundService(bg_remover=PhotoRoomBackgroundRemover()),
    )
    node.inputs = inputs  # type: ignore[assignment]

    result = await node.run()

    # Surgical write-back: only this slot's prompt + complexity change. The
    # file is re-dumped with the Writer's exact yaml settings, so every
    # other line (incl. the stale path strings) is byte-stable.
    images[slot_id]["prompt"] = result.prompt
    images[slot_id]["complexity"] = (
        result.complexity.value if result.complexity is not None else None
    )
    (run_dir / OUTPUT_FILENAME).write_text(
        yaml.safe_dump(
            output_data,
            sort_keys=False,
            allow_unicode=True,
            default_flow_style=False,
        ),
        encoding="utf-8",
    )

    print(f"\n{RULE}\nregenerated {slot_id} in {run_dir}\n{RULE}")
    print("\n--- old prompt ---\n" + old_prompt)
    print("\n--- new prompt ---\n" + result.prompt)
    print(
        f"\ncomplexity: "
        f"{result.complexity.value if result.complexity else None}"
    )
    print(f"final image: {result.path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
