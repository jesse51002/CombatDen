"""End-to-end executor tests plus the mandated schema round-trips."""

from __future__ import annotations

import asyncio
from pathlib import Path

import pytest
import yaml
from PIL import Image

from schema import (
    AbsolutePath,
    AppFormat,
    ColorOutput,
    Complexity,
    Customization,
    Output,
    RunCost,
)
from src.core.run_context import RunContext
from src.executor import orchestrator
from src.executor.orchestrator import Pipeline
from src.executor.writer import (
    APP_PROVENANCE_NAME,
    CUSTOMIZATION_PROVENANCE_NAME,
    Writer,
)
from src.modules.images.image_models import ImageComplexity, ImagePrompt

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


# Distinct known per-service costs so the aggregation is unambiguous.
_FAKE_LLM_COST = 0.001234
_FAKE_IMAGE_COST = 0.05
_FAKE_BG_COST = 0.02

# Each fake's per-model-id split. Distinct keys per service so the
# writer's merge is unambiguous and each bucket sums back to its service
# total (pure model-id keying; PhotoRoom under its synthetic key).
_FAKE_LLM_BY_MODEL = {
    "anthropic/demo-prompt": _FAKE_LLM_COST * 0.75,
    "gemini/demo-classify": _FAKE_LLM_COST * 0.25,
}
_FAKE_IMAGE_BY_MODEL = {"openai/demo-image": _FAKE_IMAGE_COST}
_FAKE_BG_BY_MODEL = {"photoroom": _FAKE_BG_COST}


class _FakeLLM:
    """Honours LLMClient: structured colour palette + image prompt + bg verdict."""

    cost = _FAKE_LLM_COST
    cost_by_model = _FAKE_LLM_BY_MODEL

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
        else:
            raise AssertionError(f"unexpected schema {schema!r}")
        return result

    async def complete(self, messages, *, tools=None, model=None):
        raise AssertionError("complete() not used in this flow")


class _FakeImageGen:
    cost = _FAKE_IMAGE_COST
    cost_by_model = _FAKE_IMAGE_BY_MODEL

    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> AbsolutePath:
        dest.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (64, 64), (10, 10, 10)).save(dest)
        return AbsolutePath(str(dest.resolve()))


class _FakeBgRemover:
    """Writes a real RGBA cutout: transparent border, opaque centred square."""

    cost = _FAKE_BG_COST
    cost_by_model = _FAKE_BG_BY_MODEL

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

    result = asyncio.run(Pipeline().run(ctx))
    output = result.output

    assert isinstance(output, Output)
    # The run exposes its paid services so the writer can total cost.
    assert result.llm.cost == _FAKE_LLM_COST
    assert result.image_gen.cost == _FAKE_IMAGE_COST
    assert result.bg_remover.cost == _FAKE_BG_COST
    assert output.app == ctx.app.id
    assert output.display_name == ctx.app.display_name
    # Every declared slot resolved.
    assert set(output.color_set.colors) == {c.id for c in ctx.app.colors}
    assert set(output.image_set.images) == {i.id for i in ctx.app.images}
    assert output.color_set.mode == ctx.cust.colors_direction.mode
    # Image paths point into this run's images dir and the files exist.
    for slot_id, img in output.image_set.images.items():
        p = Path(str(img.path))
        assert p.is_absolute() and p.exists()
        assert p.name == f"{slot_id}.png"
        assert img.prompt
        assert img.complexity is not None
        # The removed style/dependency provenance fields are gone.
        assert not hasattr(img, "adherent")
        assert not hasattr(img, "dependency_usage")


def test_writer_round_trips_provenance_and_output(tmp_path, monkeypatch):
    ctx = _run_ctx(tmp_path)
    _patch_services(monkeypatch, [c.id for c in ctx.app.colors])
    result = asyncio.run(Pipeline().run(ctx))

    Writer().write(result, ctx)

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
    # The writer stamps cost on; everything else round-trips exactly.
    assert reloaded.cost is not None
    assert reloaded.model_copy(update={"cost": None}) == result.output
    # Typed primitives unwrapped to plain strings in the YAML.
    raw = yaml.safe_load(out_yaml.read_text())
    assert raw["color_set"]["mode"] in ("light", "dark")
    any_color = next(iter(raw["color_set"]["colors"].values()))
    assert isinstance(any_color["oklch"], str)


def test_writer_writes_run_cost_breakdown(tmp_path, monkeypatch):
    """The writer sums each paid service's running cost into the optional
    ``RunCost`` (total + per-service + per-model-id breakdown) and it
    round-trips."""
    ctx = _run_ctx(tmp_path)
    _patch_services(monkeypatch, [c.id for c in ctx.app.colors])
    result = asyncio.run(Pipeline().run(ctx))

    Writer().write(result, ctx)

    raw = yaml.safe_load(ctx.output_path().read_text())
    cost = raw["cost"]
    assert cost["llm"] == pytest.approx(_FAKE_LLM_COST)
    assert cost["image_generation"] == pytest.approx(_FAKE_IMAGE_COST)
    assert cost["background_removal"] == pytest.approx(_FAKE_BG_COST)
    assert cost["total"] == pytest.approx(
        _FAKE_LLM_COST + _FAKE_IMAGE_COST + _FAKE_BG_COST
    )
    # Per-model-id breakdown: every service's buckets merged, keyed by
    # model id (PhotoRoom under its synthetic key), summing back to total.
    by_model = cost["by_model"]
    assert set(by_model) == (
        set(_FAKE_LLM_BY_MODEL)
        | set(_FAKE_IMAGE_BY_MODEL)
        | set(_FAKE_BG_BY_MODEL)
    )
    assert "photoroom" in by_model
    # Each bucket is independently rounded to COST_PRECISION (6 dp), so the
    # per-model sum equals total only modulo that rounding (as the RunCost
    # docstring states) — a real double-count/miss would be off by cents.
    assert sum(by_model.values()) == pytest.approx(cost["total"], abs=1e-5)
    # Optional field validates back through the schema.
    reloaded = Output.model_validate(raw)
    assert reloaded.cost.total == pytest.approx(cost["total"])
    assert reloaded.cost.by_model == pytest.approx(by_model)


def test_run_cost_by_model_back_compat():
    """A cost block written before ``by_model`` existed still validates;
    the field defaults to ``{}`` (same back-compat contract as the
    optional ``Output.cost`` itself)."""
    legacy = RunCost.model_validate(
        {
            "total": 0.07,
            "llm": 0.001,
            "image_generation": 0.05,
            "background_removal": 0.02,
        }
    )
    assert legacy.by_model == {}


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


def test_output_back_compat_ignores_removed_fields():
    """``extra="ignore"`` on the output models: a legacy ``output.yaml``
    that still carries the now-removed style/dependency provenance keys
    (``adherent``, ``edited_prompt``, ``edited_reason``,
    ``dependency_usage``) still validates — those keys are silently
    dropped, not rejected. ``complexity`` and ``cost`` stay optional."""
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

    # Back-compat: no optional fields at all (mode is required, though).
    old = Output.model_validate(
        {
            "app": "demo",
            "display_name": "Demo App",
            "image_set": {"images": {"hero": dict(base_image)}},
            "color_set": {"mode": "light", "colors": colors},
        }
    )
    assert old.image_set.images["hero"].complexity is None
    assert old.cost is None

    # Legacy run: still carries every removed key — all dropped, no error.
    legacy = Output.model_validate(
        {
            "app": "demo",
            "display_name": "Demo App",
            "image_set": {
                "images": {
                    "hero": {
                        **base_image,
                        "complexity": "medium",
                        "adherent": False,
                        "edited_prompt": "make the finish forged gunmetal",
                        "edited_reason": "too generic for the prompt",
                        "dependency_usage": {"sibling": "direct"},
                    }
                }
            },
            "color_set": {"mode": "dark", "colors": colors},
        }
    )
    img = legacy.image_set.images["hero"]
    assert img.prompt == base_image["prompt"]
    assert img.complexity is not None
    for removed in (
        "adherent",
        "edited_prompt",
        "edited_reason",
        "dependency_usage",
    ):
        assert not hasattr(img, removed)
