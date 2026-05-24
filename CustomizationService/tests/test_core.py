"""Light, deterministic tests for the offline core (no network)."""

from __future__ import annotations

from pathlib import Path

import pytest

from schema import AppFormat, Customization
from src.core.errors import PipelineError
from src.core.run_context import RunContext
from src.core.util import load_yaml

# Committed fixture tree — never the live ``apps/`` production runs.
_FIXTURE_APP = Path(__file__).resolve().parent / "data" / "apps" / "demo"
APP_YAML = _FIXTURE_APP / "app.yaml"
CUST_YAML = _FIXTURE_APP / "customization.yaml"


def test_load_yaml_happy_path(tmp_path: Path) -> None:
    target = tmp_path / "doc.yaml"
    target.write_text("a: 1\nb: two\n", encoding="utf-8")

    data = load_yaml(target)

    assert data == {"a": 1, "b": "two"}


def test_load_yaml_rejects_non_mapping(tmp_path: Path) -> None:
    target = tmp_path / "list.yaml"
    target.write_text("- one\n- two\n", encoding="utf-8")

    with pytest.raises(PipelineError):
        load_yaml(target)


def test_load_yaml_missing_file(tmp_path: Path) -> None:
    with pytest.raises(PipelineError):
        load_yaml(tmp_path / "does_not_exist.yaml")


def test_run_context_derives_paths(tmp_path: Path) -> None:
    app = AppFormat.model_validate(load_yaml(APP_YAML))
    cust = Customization.model_validate(load_yaml(CUST_YAML))

    ctx = RunContext(app, cust, tmp_path)

    assert ctx.run_dir.is_dir()
    assert ctx.image_dir.is_dir()
    assert ctx.final_image_dir.is_dir()
    assert ctx.icon_dir.is_dir()
    assert ctx.app_id == "demo"

    img = str(ctx.image_path("hero"))
    assert img.endswith("/final_images/hero.png")
    assert img.startswith("/")

    icon = str(ctx.icon_path("home_tab"))
    assert icon.endswith("/icons/home_tab.svg")
    assert icon.startswith("/")

    assert str(ctx.output_path()).endswith("output.yaml")
