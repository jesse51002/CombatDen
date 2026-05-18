"""Light, deterministic tests for the offline core (no network)."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml
from PIL import Image

from schema import AppFormat, Customization
from src.core.errors import PipelineError
from src.core.imaging import (
    TRANSPARENT_ALPHA_MAX,
    autocrop,
    transparent_fraction,
)
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
    assert ctx.app_id == "demo"

    img = str(ctx.image_path("hero"))
    assert img.endswith("/final_images/hero.png")
    assert img.startswith("/")

    assert str(ctx.output_path()).endswith("output.yaml")


def test_autocrop_crops_tight_to_subject(tmp_path: Path) -> None:
    src = tmp_path / "src.png"
    dst = tmp_path / "dst.png"

    size = 100
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    # Opaque rectangle off-centre: x in [10, 30), y in [60, 80). The old
    # symmetric crop would have produced an 80x60 centred frame; the tight
    # crop is exactly the subject's bbox.
    for x in range(10, 30):
        for y in range(60, 80):
            canvas.putpixel((x, y), (255, 0, 0, 255))
    canvas.save(src)

    autocrop(src, dst)

    out = Image.open(dst)
    ow, oh = out.size
    # Tight to the bbox: 20x20, not symmetric/centred.
    assert (ow, oh) == (20, 20)
    # The subject fills the whole cropped frame.
    assert out.convert("RGBA").getbbox() == (0, 0, ow, oh)


def test_transparent_fraction_opaque_is_zero(tmp_path: Path) -> None:
    src = tmp_path / "opaque.png"
    Image.new("RGBA", (40, 40), (10, 20, 30, 255)).save(src)
    assert transparent_fraction(src) == 0.0


def test_transparent_fraction_fully_transparent_is_one(tmp_path: Path) -> None:
    src = tmp_path / "clear.png"
    Image.new("RGBA", (40, 40), (0, 0, 0, 0)).save(src)
    assert transparent_fraction(src) == 1.0


def test_transparent_fraction_half(tmp_path: Path) -> None:
    src = tmp_path / "half.png"
    img = Image.new("RGBA", (40, 40), (255, 0, 0, 255))
    # Left half fully transparent.
    for x in range(20):
        for y in range(40):
            img.putpixel((x, y), (0, 0, 0, 0))
    img.save(src)
    assert transparent_fraction(src) == pytest.approx(0.5)


def test_transparent_fraction_counts_faint_fringe(tmp_path: Path) -> None:
    """Alpha at/below TRANSPARENT_ALPHA_MAX still counts as transparent."""
    src = tmp_path / "fringe.png"
    Image.new("RGBA", (10, 10), (0, 0, 0, TRANSPARENT_ALPHA_MAX)).save(src)
    assert transparent_fraction(src) == 1.0


def test_autocrop_fully_transparent_copied(tmp_path: Path) -> None:
    src = tmp_path / "blank.png"
    dst = tmp_path / "blank_out.png"

    Image.new("RGBA", (20, 30), (0, 0, 0, 0)).save(src)

    autocrop(src, dst)

    out = Image.open(dst)
    assert out.size == (20, 30)
    assert out.convert("RGBA").getbbox() is None
