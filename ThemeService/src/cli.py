"""CLI entrypoint — the only user-facing surface over the async core."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path

from src.core.errors import PipelineError
from src.core.logging_setup import configure_logging
from src.core.run_context import OUTPUT_ROOT_DIRNAME, RunContext
from src.core.util import load_yaml
from src.executor.orchestrator import Pipeline
from src.executor.writer import Writer
from schema import AppFormat, Customization

logger = logging.getLogger(__name__)

# Default output root: <package parent>/apps -> apps/<app_id>/<run_id>/
DEFAULT_OUT_ROOT = Path(__file__).resolve().parent.parent / OUTPUT_ROOT_DIRNAME
# A run name becomes a single folder segment under <out_root>/<app_id>/, so it
# must not be empty or carry a path separator / parent-dir escape.
ILLEGAL_RUN_NAME_CHARS = ("/", "\\", "..")


def _existing_category(output_path: Path) -> str | None:
    """The ``category`` on a pre-existing run's ``output.yaml``, if any.

    A full run pointed at an existing dir overwrites its ``output.yaml`` (the
    pipeline clears the file up front), so the prior value has to be read
    before that happens. It is the writer's **fallback**, not an override: an
    app that declares a ``categories`` vocabulary re-classifies through the
    pipeline's classification node like every other slot, and this value is
    used only if that produced nothing — the app declares no vocabulary, or
    the node failed. Either way the re-run keeps the theme in the picker
    instead of dropping it.

    Returns ``None`` when there is no prior run, the file is unreadable /
    malformed, or it carries no ``category``.
    """
    if not output_path.is_file():
        return None
    try:
        data = load_yaml(output_path)
    except PipelineError:
        return None
    category = data.get("category")
    return category if isinstance(category, str) else None


def _run_name(value: str) -> str:
    """argparse type: validate ``--run-name`` is one safe folder segment."""
    if not value or any(token in value for token in ILLEGAL_RUN_NAME_CHARS):
        raise argparse.ArgumentTypeError(
            f"run name {value!r} must be a non-empty single folder segment "
            "with no '/', '\\', or '..'"
        )
    return value


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    """Define and parse the CLI arguments."""
    parser = argparse.ArgumentParser(
        prog="src",
        description="Customize an app from a brand brief (colors + images).",
    )
    parser.add_argument(
        "--app-yaml",
        required=True,
        type=Path,
        help="Path to the app slot manifest (app.yaml).",
    )
    parser.add_argument(
        "--customization-yaml",
        required=True,
        type=Path,
        help="Path to the brand brief (customization.yaml).",
    )
    parser.add_argument(
        "--out-root",
        type=Path,
        default=DEFAULT_OUT_ROOT,
        help=f"Output root (default: {DEFAULT_OUT_ROOT}).",
    )
    parser.add_argument(
        "--run-name",
        type=_run_name,
        default=None,
        help=(
            "Name the run folder (default: a UTC timestamp). Pointing it at an "
            "existing run does a full in-place re-run, overwriting that "
            "folder's produced artifacts."
        ),
    )
    return parser.parse_args(argv)


async def main(argv: list[str] | None = None) -> int:
    """Run the pipeline and return a process exit code."""
    args = _parse_args(argv)
    configure_logging()

    # Read + validate inline (load_yaml is the only reusable bit); the run
    # context then carries the models + paths everywhere downstream.
    run_ctx = RunContext(
        AppFormat.model_validate(load_yaml(args.app_yaml)),
        Customization.model_validate(load_yaml(args.customization_yaml)),
        args.out_root,
        run_id=args.run_name,
    )

    # A full run pointed at an existing dir overwrites its output.yaml, so
    # capture the prior run's category BEFORE the pipeline clears that file.
    # The writer uses it only as a fallback (the classification node produces
    # the category now); see Writer._resolve_category.
    prior_category = _existing_category(run_ctx.output_path())

    result = await Pipeline().run(run_ctx)
    Writer().write(result, run_ctx, prior_category=prior_category)

    logger.debug("done: %s", run_ctx.output_path())
    return 0
