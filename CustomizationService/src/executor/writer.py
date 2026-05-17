"""Writer — serializes a run's YAML artifacts in one call."""

from __future__ import annotations

import logging
from pathlib import Path

import yaml
from pydantic import BaseModel

from src.core.run_context import RunContext
from schema import Output

logger = logging.getLogger(__name__)

APP_PROVENANCE_NAME = "app.yaml"
CUSTOMIZATION_PROVENANCE_NAME = "customization.yaml"


def _dump_model(model: BaseModel, path: Path) -> None:
    """Serialize one validated model to readable YAML at ``path``."""
    path.write_text(
        yaml.safe_dump(
            model.model_dump(mode="json"),
            sort_keys=False,
            allow_unicode=True,
            default_flow_style=False,
        ),
        encoding="utf-8",
    )


class Writer:
    """Writes provenance + output for one run, together."""

    def write(self, output: Output, run_ctx: RunContext) -> None:
        """Serialize the canonical provenance and the resolved output."""
        app_path = run_ctx.run_dir / APP_PROVENANCE_NAME
        cust_path = run_ctx.run_dir / CUSTOMIZATION_PROVENANCE_NAME
        output_path = run_ctx.output_path()

        _dump_model(run_ctx.app, app_path)
        _dump_model(run_ctx.cust, cust_path)
        _dump_model(output, output_path)

        logger.debug(
            "wrote provenance + output: %s, %s, %s",
            app_path,
            cust_path,
            output_path,
        )
