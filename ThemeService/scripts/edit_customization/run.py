"""Edit a ``customization.yaml`` brief in place — a validated, targeted edit.

The brief is the one hand-editable *input*, but edits still go through a
validated path rather than raw text munging: this loads the file, applies only
the flags you pass (every other field unchanged), re-validates against the
``Customization`` model, and writes it back. The five editable fields are
**flattened** — no nested ``design_direction`` / ``colors_direction`` to type.

It edits the brief and nothing else — it regenerates no slots and never touches
``output.yaml``. To apply a brief change to a run, edit that run dir's
``customization.yaml`` here, then ``regen`` the affected slots (or do a full
pipeline run).

Run from the package root (so imports resolve):

    poetry run python scripts/edit_customization/run.py \\
        --file apps/<app_id>/customization.yaml \\
        [--name "…"] [--short-desc "…"] [--long-desc "…"] \\
        [--colors-description "…"] [--mode light|dark]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml
from pydantic import ValidationError

# Standalone entrypoint two levels under the repo root: make `src`/`schema`
# importable regardless of how the venv installed them.
_REPO_ROOT = Path(__file__).resolve().parents[2]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from schema import Customization
from schema.color_mode import ColorMode
from src.core.errors import PipelineError
from src.core.util import load_yaml

RULE = "=" * 72

# Flattened CLI flag → (group, field) on Customization. The whole editable
# surface: Customization only has these five fields.
_FIELD_MAP: dict[str, tuple[str, str]] = {
    "name": ("design_direction", "name"),
    "short_desc": ("design_direction", "short_desc"),
    "long_desc": ("design_direction", "long_desc"),
    "colors_description": ("colors_direction", "description"),
    "mode": ("colors_direction", "mode"),
}


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="edit_customization",
        description=(
            "Edit a customization.yaml brief in place: apply the given flags, "
            "re-validate, write back. Edits the brief only — regenerates "
            "nothing."
        ),
    )
    parser.add_argument(
        "--file",
        required=True,
        type=Path,
        help="The customization.yaml to edit in place (e.g. "
        "apps/<app_id>/customization.yaml).",
    )
    parser.add_argument("--name", help="design_direction.name")
    parser.add_argument(
        "--short-desc", dest="short_desc", help="design_direction.short_desc"
    )
    parser.add_argument(
        "--long-desc", dest="long_desc", help="design_direction.long_desc"
    )
    parser.add_argument(
        "--colors-description",
        dest="colors_description",
        help="colors_direction.description",
    )
    parser.add_argument(
        "--mode",
        choices=[m.value for m in ColorMode],
        help="colors_direction.mode",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    path: Path = args.file
    if not path.is_file():
        raise SystemExit(f"no such file: {path}")

    # The file must already be a valid brief — we edit, not author from broken.
    try:
        current = Customization.model_validate(load_yaml(path))
    except PipelineError as exc:
        raise SystemExit(str(exc))
    except ValidationError as exc:
        raise SystemExit(
            f"{path} is not a valid customization.yaml; fix it (or use the "
            f"brand-brief skill to author one) before editing:\n{exc}"
        )

    data = current.model_dump(mode="json")
    changed: list[str] = []
    for flag, (group, field) in _FIELD_MAP.items():
        value = getattr(args, flag)
        if value is not None:
            data[group][field] = value
            changed.append(f"{group}.{field}")

    print(f"\n{RULE}\nedit_customization {path}\n{RULE}")
    if not changed:
        print("no fields given — nothing changed.")
        return 0

    # Re-validate the merged brief; a bad edit never lands.
    try:
        updated = Customization.model_validate(data)
    except ValidationError as exc:
        raise SystemExit(f"edit would make {path} invalid:\n{exc}")

    path.write_text(
        yaml.safe_dump(
            updated.model_dump(mode="json"),
            sort_keys=False,
            allow_unicode=True,
            default_flow_style=False,
        ),
        encoding="utf-8",
    )
    print(f"edited: {changed}")
    print(f"\n(to apply to a run, `regen` the affected slots or do a full run.)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
