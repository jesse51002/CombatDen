"""Read the hand-authored gym files from disk.

The gym configs stay git-tracked YAML (`gyms/<gym_id>.yaml`) as the human source
of truth; ``gym-check`` validates them and ``sync-gyms`` loads them into SQL. The
read API no longer touches these files (it queries the DB), so this small loader
lives with the scripts that DO read the YAML, not in the API service.
"""

from __future__ import annotations

from pathlib import Path

import yaml

from schema import Gym

GYMS_DIRNAME = "gyms"


def gyms_dir(root: Path) -> Path:
    """The directory holding ``<gym_id>.yaml`` files."""
    return root / GYMS_DIRNAME


def list_gym_ids(root: Path) -> list[str]:
    """Every authored gym id (YAML filename stem), sorted. Empty if no dir."""
    directory = gyms_dir(root)
    if not directory.is_dir():
        return []
    return sorted(f.stem for f in directory.glob("*.yaml"))


def load_gym_yaml(root: Path, gym_id: str) -> Gym:
    """Load + validate one authored gym file against the ``Gym`` model.

    Raises ``FileNotFoundError`` if absent and ``pydantic.ValidationError`` /
    ``yaml.YAMLError`` if it doesn't round-trip the schema.
    """
    path = gyms_dir(root) / f"{gym_id}.yaml"
    if not path.is_file():
        raise FileNotFoundError(f"no gym file {path}")
    return Gym.model_validate(yaml.safe_load(path.read_text(encoding="utf-8")))
