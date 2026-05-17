"""Light, deterministic tests for the offline core (no network)."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from PIL import Image

from schema import AppFormat, Customization
from src.core.errors import PipelineError
from src.core.imaging import autocrop_symmetric
from src.core.run_context import RunContext
from src.core.util import load_yaml

APP_YAML = Path("apps/combatden/app.yaml")
CUST_YAML = Path("apps/combatden/customization.yaml")


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
    assert ctx.app_id == "combatden"

    img = str(ctx.image_path("logo_primary"))
    assert img.endswith("/final_images/logo_primary.png")
    assert img.startswith("/")

    assert str(ctx.output_path()).endswith("output.yaml")


def test_autocrop_symmetric_centres_subject(tmp_path: Path) -> None:
    src = tmp_path / "src.png"
    dst = tmp_path / "dst.png"

    size = 100
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Opaque square centred at (50, 50), spanning [30, 70).
    for x in range(30, 70):
        for y in range(30, 70):
            canvas.putpixel((x, y), (255, 0, 0, 255))
    canvas.save(src)

    autocrop_symmetric(src, dst)

    out = Image.open(dst)
    ow, oh = out.size
    # Smaller free margin per axis is 30; symmetric crop -> 100 - 2*30 = 40.
    assert ow == 40 and oh == 40
    assert ow < size and oh < size
    # Subject still fills the cropped frame, centred (its bbox == full frame).
    assert out.convert("RGBA").getbbox() == (0, 0, ow, oh)


def test_autocrop_symmetric_fully_transparent_copied(tmp_path: Path) -> None:
    src = tmp_path / "blank.png"
    dst = tmp_path / "blank_out.png"

    Image.new("RGBA", (20, 30), (0, 0, 0, 0)).save(src)

    autocrop_symmetric(src, dst)

    out = Image.open(dst)
    assert out.size == (20, 30)
    assert out.convert("RGBA").getbbox() is None
