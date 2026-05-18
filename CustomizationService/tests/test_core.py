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
    gridtrim_autocrop,
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


def test_gridtrim_autocrop_trims_halo_tighter_than_autocrop(
    tmp_path: Path,
) -> None:
    src = tmp_path / "src.png"
    auto_dst = tmp_path / "auto.png"
    grid_dst = tmp_path / "grid.png"

    canvas = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    # Faint low-alpha smudge filling a far corner cell (pure halo).
    for x in range(32):
        for y in range(32):
            canvas.putpixel((x, y), (0, 0, 0, 8))
    # Opaque subject, one whole 32px cell, away from the smudge.
    for x in range(64, 96):
        for y in range(64, 96):
            canvas.putpixel((x, y), (255, 0, 0, 255))
    canvas.save(src)

    autocrop(src, auto_dst)
    gridtrim_autocrop(src, grid_dst)

    auto = Image.open(auto_dst)
    grid = Image.open(grid_dst)
    # autocrop's bbox is held loose by the faint corner smudge (alpha>0).
    assert auto.size == (96, 96)
    # The grid pass drops the all-halo border cells -> tight to subject.
    assert grid.size == (32, 32)
    assert grid.convert("RGBA").getbbox() == (0, 0, 32, 32)
    assert grid.size[0] * grid.size[1] < auto.size[0] * auto.size[1]


def test_gridtrim_autocrop_opaque_is_noop(tmp_path: Path) -> None:
    src = tmp_path / "opaque.png"
    dst = tmp_path / "opaque_out.png"
    Image.new("RGBA", (64, 64), (10, 20, 30, 255)).save(src)

    gridtrim_autocrop(src, dst)

    out = Image.open(dst)
    # No halo -> no red cells -> nothing trimmed, same extent.
    assert out.size == (64, 64)
    assert out.convert("RGBA").getbbox() == (0, 0, 64, 64)


def test_gridtrim_autocrop_fully_transparent_copied(tmp_path: Path) -> None:
    src = tmp_path / "blank.png"
    dst = tmp_path / "blank_out.png"
    Image.new("RGBA", (20, 30), (0, 0, 0, 0)).save(src)

    gridtrim_autocrop(src, dst)

    out = Image.open(dst)
    assert out.size == (20, 30)
    assert out.convert("RGBA").getbbox() is None


def test_gridtrim_autocrop_all_red_copies_bbox_unchanged(
    tmp_path: Path,
) -> None:
    src = tmp_path / "faint.png"
    dst = tmp_path / "faint_out.png"
    # Uniform faint alpha: getbbox() is non-empty (alpha>0) but every grid
    # cell is pure halo -> keep the alpha-bbox crop, never a zero-size image.
    Image.new("RGBA", (50, 50), (0, 0, 0, 8)).save(src)

    gridtrim_autocrop(src, dst)

    out = Image.open(dst)
    assert out.size == (50, 50)


def test_gridtrim_autocrop_partial_edge_cells(tmp_path: Path) -> None:
    src = tmp_path / "partial.png"
    dst = tmp_path / "partial_out.png"

    # 100 is not divisible by the 32px cell -> the last column/row is a
    # 4px partial cell. The subject runs to the very edge through it.
    canvas = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    # Faint smudge in the opposite corner cell, holding autocrop's bbox
    # loose so the grid pass has a border to trim.
    for x in range(32):
        for y in range(32):
            canvas.putpixel((x, y), (0, 0, 0, 8))
    # Opaque subject filling the bottom-right, ending inside the partial
    # edge cells at x/y == 100.
    for x in range(40, 100):
        for y in range(40, 100):
            canvas.putpixel((x, y), (0, 200, 0, 255))
    canvas.save(src)

    gridtrim_autocrop(src, dst)

    out = Image.open(dst)
    # Tight to the 60x60 subject: proves the surviving box uses the
    # clamped partial-cell extent (==100), not col*GRID_CELL_PX (==96).
    assert out.size == (60, 60)
    assert out.convert("RGBA").getbbox() == (0, 0, 60, 60)


def test_gridtrim_autocrop_keeps_interior_hole(tmp_path: Path) -> None:
    src = tmp_path / "hole.png"
    dst = tmp_path / "hole_out.png"
    canvas = Image.new("RGBA", (96, 96), (10, 20, 30, 255))
    # A faint interior cell, fully surrounded by opaque subject. A
    # rectangular crop cannot carve it out -> the extent is preserved.
    for x in range(32, 64):
        for y in range(32, 64):
            canvas.putpixel((x, y), (0, 0, 0, 8))
    canvas.save(src)

    gridtrim_autocrop(src, dst)

    out = Image.open(dst)
    assert out.size == (96, 96)


def test_gridtrim_autocrop_smaller_than_one_cell(tmp_path: Path) -> None:
    src = tmp_path / "tiny.png"
    dst = tmp_path / "tiny_out.png"
    Image.new("RGBA", (16, 16), (200, 50, 50, 255)).save(src)

    gridtrim_autocrop(src, dst)

    out = Image.open(dst)
    assert out.size == (16, 16)
    assert out.convert("RGBA").getbbox() == (0, 0, 16, 16)
