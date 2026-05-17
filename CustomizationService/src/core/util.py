"""Small shared helpers (YAML loading)."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

import yaml

from src.core.errors import PipelineError

logger = logging.getLogger(__name__)


def load_yaml(path: Path) -> dict[str, Any]:
    """Read one YAML file into a plain mapping.

    Raises:
        PipelineError: the file is missing, unreadable, malformed, or its
            top level is not a mapping.
    """
    try:
        with path.open("r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
    except OSError as exc:
        raise PipelineError(f"could not read YAML file {path}: {exc}") from exc
    except yaml.YAMLError as exc:
        raise PipelineError(f"malformed YAML in {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise PipelineError(
            f"YAML top level in {path} must be a mapping; "
            f"got {type(data).__name__}"
        )
    return data
