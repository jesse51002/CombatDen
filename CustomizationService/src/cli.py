"""CLI entrypoint — the only user-facing surface over the async core."""

from __future__ import annotations

import argparse
import logging
from pathlib import Path

from src.core.logging_setup import configure_logging
from src.core.run_context import RunContext
from src.core.util import load_yaml
from src.executor.orchestrator import Pipeline
from src.executor.writer import Writer
from schema import AppFormat, Customization

logger = logging.getLogger(__name__)

# Default output root: <package parent>/apps -> apps/<app_id>/<run_id>/
DEFAULT_OUT_ROOT = Path(__file__).resolve().parent.parent / "apps"


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
    )

    result = await Pipeline().run(run_ctx)
    Writer().write(result, run_ctx)

    logger.debug("done: %s", run_ctx.output_path())
    return 0
