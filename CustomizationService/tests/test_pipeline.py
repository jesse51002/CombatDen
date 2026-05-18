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
    Complexity,
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
from src.modules.images.image_models import (
    ImageComplexity,
    ImagePrompt,
    StyleCheck,
)

# Committed fixture tree — never the live ``apps/`` production runs.
APP_DIR = Path(__file__).resolve().parent / "data" / "apps" / "demo"
# The resolved Output lives in a run subdir; the committed baseline
# run is "default".
DEFAULT_OUTPUT = APP_DIR / "default" / "output.yaml"


def _run_ctx(tmp_path: Path) -> RunContext:
    app = AppFormat.model_validate(yaml.safe_load((APP_DIR / "app.yaml").read_text()))
    cust = Customization.model_validate(
        yaml.safe_load((APP_DIR / "customization.yaml").read_text())
    )
    return RunContext(app, cust, tmp_path)


def _palette_oklch(slot_id: str) -> str:
    """Contract-satisfying oklch for the demo (dark-mode) slots."""
    if slot_id == "background":
        return "oklch(15% 0.012 40)"
    if slot_id == "text":
        return "oklch(92% 0.01 80)"
    return "oklch(52% 0.16 25)"  # primary/accent — unconstrained


class _FakeLLM:
    """Honours LLMClient: structured colour palette + image prompt + bg verdict."""

    def __init__(self, color_slot_ids: list[str]) -> None:
        self._color_slot_ids = color_slot_ids

    async def complete_structured(
        self, messages, *, schema, model=None
    ):
        if getattr(schema, "__name__", "") == "ColorPalette":
            # Per-request closed model: one field per requested slot id.
            # Constructing it runs the deterministic contract validator.
            result = schema(
                **{
                    sid: ColorOutput(
                        oklch=_palette_oklch(sid),
                        display_name=f"{sid} tone",
                        description="on-brand demo colour",
                    )
                    for sid in self._color_slot_ids
                }
            )
        elif schema is ImagePrompt:
            result = ImagePrompt(
                prompt="studio shot of the subject on a plain solid background",
            )
        elif schema is ImageComplexity:
            result = ImageComplexity(complexity=Complexity.MEDIUM)
        elif schema is StyleCheck:
            # Adherent: the conditional edit path stays out of the
            # happy-path assembly test.
            result = StyleCheck(
                adherent=True, reason="", edit_instruction=""
            )
        else:
            raise AssertionError(f"unexpected schema {schema!r}")
        return result

    async def complete(self, messages, *, tools=None, model=None):
        raise AssertionError("complete() not used in this flow")


class _FakeImageGen:
    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> AbsolutePath:
        dest.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (64, 64), (10, 10, 10)).save(dest)
        return AbsolutePath(str(dest.resolve()))

    async def edit(
        self, src: Path, instruction: str, dest: Path, *, model: str
    ) -> AbsolutePath:
        # Unused on the adherent happy path; present to honour the contract.
        dest.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (64, 64), (20, 20, 20)).save(dest)
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
        orchestrator, "LiteLLMClient", lambda: _FakeLLM(color_slot_ids)
    )
    monkeypatch.setattr(
        orchestrator, "LiteLLMImageGenerator", lambda: _FakeImageGen()
    )
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
        # Style verdict always set by a fresh run; adherent ⇒ no edit.
        assert img.adherent is True
        assert img.edited_prompt is None and img.edited_reason is None


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
    assert isinstance(any_color["oklch"], str)


def test_demo_examples_round_trip():
    """Every committed demo fixture validates against its schema."""
    assert AppFormat.model_validate(
        yaml.safe_load((APP_DIR / "app.yaml").read_text())
    )
    assert Customization.model_validate(
        yaml.safe_load((APP_DIR / "customization.yaml").read_text())
    )
    assert Output.model_validate(
        yaml.safe_load(DEFAULT_OUTPUT.read_text())
    )


def test_output_style_fields_optional_and_back_compat():
    """Old output.yaml (no style fields) still validates; a new one with
    them validates too — the fields are optional like ``complexity``."""
    base_image = {
        "path": "/fixture/demo/default/final_images/hero.png",
        "prompt": "A bold demo hero illustration on a flat solid background.",
    }
    colors = {
        "primary": {
            "oklch": "oklch(70% 0.19 41)",
            "display_name": "Cage Orange",
            "description": "Primary brand accent.",
        }
    }

    # Back-compat: no style fields at all.
    old = Output.model_validate(
        {
            "app": "demo",
            "display_name": "Demo App",
            "images": {"hero": {**base_image, "complexity": "medium"}},
            "colors": colors,
        }
    )
    assert old.images["hero"].adherent is None

    # New run: adherent, no edit.
    adherent = Output.model_validate(
        {
            "app": "demo",
            "display_name": "Demo App",
            "images": {
                "hero": {
                    **base_image,
                    "complexity": "medium",
                    "adherent": True,
                }
            },
            "colors": colors,
        }
    )
    assert adherent.images["hero"].adherent is True

    # New run: off-style, one edit applied — provenance present.
    edited = Output.model_validate(
        {
            "app": "demo",
            "display_name": "Demo App",
            "images": {
                "hero": {
                    **base_image,
                    "complexity": "medium",
                    "adherent": False,
                    "edited_prompt": "make the finish forged gunmetal",
                    "edited_reason": "too generic for the prompt",
                }
            },
            "colors": colors,
        }
    )
    img = edited.images["hero"]
    assert img.adherent is False
    assert img.edited_prompt == "make the finish forged gunmetal"
    assert img.edited_reason == "too generic for the prompt"
