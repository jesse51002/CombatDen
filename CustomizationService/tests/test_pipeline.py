"""End-to-end executor tests plus the mandated schema round-trips."""

from __future__ import annotations

import asyncio
from pathlib import Path

import yaml
from PIL import Image

from schema import (
    AbsolutePath,
    AppFormat,
    ColorOutput,
    Customization,
    Output,
)
from src.core.run_context import RunContext
from src.executor import orchestrator
from src.executor.orchestrator import Pipeline
from src.executor.writer import (
    APP_PROVENANCE_NAME,
    CUSTOMIZATION_PROVENANCE_NAME,
    Writer,
)
from src.modules.images.image_models import BackgroundCheck, ImagePrompt

APP_DIR = Path(__file__).resolve().parent.parent / "apps" / "combatden"


def _run_ctx(tmp_path: Path) -> RunContext:
    app = AppFormat.model_validate(yaml.safe_load((APP_DIR / "app.yaml").read_text()))
    cust = Customization.model_validate(
        yaml.safe_load((APP_DIR / "customization.yaml").read_text())
    )
    return RunContext(app, cust, tmp_path)


class _FakeLLM:
    """Honours LLMClient: structured colour palette + image prompt + bg verdict."""

    def __init__(self, color_slot_ids: list[str]) -> None:
        self._color_slot_ids = color_slot_ids

    async def complete_structured(
        self, messages, *, schema, model=None
    ):
        if getattr(schema, "__name__", "") == "ColorPalette":
            # Per-request closed model: one field per requested slot id.
            result = schema(
                **{
                    sid: ColorOutput(
                        hex="#8B2E1F", description="deep red", vibe="gritty"
                    )
                    for sid in self._color_slot_ids
                }
            )
        elif schema is ImagePrompt:
            result = ImagePrompt(
                prompt="studio shot of the subject on a plain solid background",
                rationale="isolated subject cuts out cleanly and stays on-brand",
            )
        elif schema is BackgroundCheck:
            result = BackgroundCheck(ok=True, reason="clean cutout")
        else:
            raise AssertionError(f"unexpected schema {schema!r}")
        return result

    async def complete(self, messages, *, tools=None, model=None):
        raise AssertionError("complete() not used in this flow")


class _FakeImageGen:
    async def generate(self, prompt: str, dest: Path) -> AbsolutePath:
        dest.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (64, 64), (10, 10, 10)).save(dest)
        return AbsolutePath(str(dest.resolve()))


class _FakeBgRemover:
    """Writes a real RGBA cutout: transparent border, opaque centred square."""

    async def remove(self, src: Path, dst: Path) -> None:
        dst.parent.mkdir(parents=True, exist_ok=True)
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        for x in range(20, 44):
            for y in range(20, 44):
                img.putpixel((x, y), (200, 30, 30, 255))
        img.save(dst)


def _patch_services(monkeypatch, color_slot_ids: list[str]) -> None:
    monkeypatch.setattr(
        orchestrator, "ProxyLLMClient", lambda: _FakeLLM(color_slot_ids)
    )
    monkeypatch.setattr(orchestrator, "BflImageGenerator", lambda: _FakeImageGen())
    monkeypatch.setattr(
        orchestrator, "PhotoRoomBackgroundRemover", lambda: _FakeBgRemover()
    )


def test_pipeline_run_assembles_valid_output(tmp_path, monkeypatch):
    ctx = _run_ctx(tmp_path)
    _patch_services(monkeypatch, [c.id for c in ctx.app.colors])

    output = asyncio.run(Pipeline().run(ctx))

    assert isinstance(output, Output)
    assert output.app == ctx.app.id
    assert output.display_name == ctx.app.display_name
    # Every declared slot resolved.
    assert set(output.colors) == {c.id for c in ctx.app.colors}
    assert set(output.images) == {i.id for i in ctx.app.images}
    # Image paths point into this run's images dir and the files exist.
    for slot_id, img in output.images.items():
        p = Path(str(img.path))
        assert p.is_absolute() and p.exists()
        assert p.name == f"{slot_id}.png"
        assert img.prompt


def test_writer_round_trips_provenance_and_output(tmp_path, monkeypatch):
    ctx = _run_ctx(tmp_path)
    _patch_services(monkeypatch, [c.id for c in ctx.app.colors])
    output = asyncio.run(Pipeline().run(ctx))

    Writer().write(output, ctx)

    app_yaml = ctx.run_dir / APP_PROVENANCE_NAME
    cust_yaml = ctx.run_dir / CUSTOMIZATION_PROVENANCE_NAME
    out_yaml = ctx.output_path()
    assert app_yaml.exists() and cust_yaml.exists() and out_yaml.exists()

    # Provenance equals exactly what the run consumed; output re-validates.
    assert AppFormat.model_validate(yaml.safe_load(app_yaml.read_text())) == ctx.app
    assert (
        Customization.model_validate(yaml.safe_load(cust_yaml.read_text())) == ctx.cust
    )
    reloaded = Output.model_validate(yaml.safe_load(out_yaml.read_text()))
    assert reloaded == output
    # Typed primitives unwrapped to plain strings in the YAML.
    raw = yaml.safe_load(out_yaml.read_text())
    any_color = next(iter(raw["colors"].values()))
    assert isinstance(any_color["hex"], str)


def test_combatden_examples_round_trip():
    """CLAUDE.md mandate: every apps/combatden example validates."""
    assert AppFormat.model_validate(
        yaml.safe_load((APP_DIR / "app.yaml").read_text())
    )
    assert Customization.model_validate(
        yaml.safe_load((APP_DIR / "customization.yaml").read_text())
    )
    assert Output.model_validate(
        yaml.safe_load((APP_DIR / "output.yaml").read_text())
    )
