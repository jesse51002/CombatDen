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
    ColorRole,
    Complexity,
    Customization,
    OklchColor,
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
from src.modules.colors.color_models import LLMSlotResponse
from src.modules.fonts.font_models import LLMFontResponse
from src.modules.images.image_models import ImageComplexity, ImagePrompt
from src.modules.texts.text_models import LLMTextResponse
from src.shared.interfaces.google_fonts_catalog import GoogleFontMetadata

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


def _palette_oklch(slot_id: str) -> OklchColor:
    """Contract-satisfying oklch for the demo (dark-mode) slots, as a
    structured ``OklchColor`` (the LLM wire shape now)."""
    if slot_id == "background":
        return OklchColor.from_css("oklch(15% 0.012 40)")
    if slot_id == "text":
        return OklchColor.from_css("oklch(92% 0.01 80)")
    return OklchColor.from_css("oklch(52% 0.16 25)")  # primary/accent


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
    """Honours LLMClient: structured colour palette + font selection +
    text rewrites + image prompt + bg verdict."""

    cost = _FAKE_LLM_COST
    cost_by_model = _FAKE_LLM_BY_MODEL

    def __init__(
        self,
        color_slot_ids: list[str],
        font_slot_ids: list[str],
        text_slot_ids: list[str] | None = None,
    ) -> None:
        self._color_slot_ids = color_slot_ids
        self._font_slot_ids = font_slot_ids
        # Text slots are optional on the fake the same way they are on
        # AppFormat: a run with no text slots never builds a TextNode,
        # so the fake never sees a TextSelection schema.
        self._text_slot_ids = text_slot_ids or []

    async def complete_structured(
        self, messages, *, schema, model=None
    ):
        if getattr(schema, "__name__", "") == "ColorPalette":
            # Per-request closed model: one field per requested slot id.
            # The wire shape per slot is the narrow LLMSlotResponse (the
            # LLM only emits oklch + prose; derivations, hsl, rgb, and the
            # flat palette are computed post-call by the derivation service).
            # Constructing the model runs the deterministic contract.
            result = schema(
                **{
                    sid: LLMSlotResponse(
                        oklch=_palette_oklch(sid),
                        display_name=f"{sid} tone",
                        description="on-brand demo colour",
                    )
                    for sid in self._color_slot_ids
                }
            )
        elif getattr(schema, "__name__", "") == "FontSelection":
            # Per-request closed model for fonts: one LLMFontResponse per
            # font slot. Constructing the model runs the Google-Fonts
            # membership validator — the fake catalog below contains the
            # families we hand back here.
            result = schema(
                **{
                    sid: LLMFontResponse(
                        family=_FAKE_FONT_FAMILY[sid],
                        display_name=f"{sid} pick",
                        description=f"on-brand demo font for {sid}",
                    )
                    for sid in self._font_slot_ids
                }
            )
        elif getattr(schema, "__name__", "") == "TextSelection":
            # Per-request closed model for texts: one LLMTextResponse per
            # text slot the service asked about. The closed schema only
            # contains the fields the service requested, so the per-slot
            # retry loop will narrow the request set across attempts; we
            # return a canned value per asked-for slot, sized to fit each
            # slot's bounds in the demo fixture.
            requested = list(schema.model_fields)
            result = schema(
                **{
                    sid: LLMTextResponse(value=_FAKE_TEXT_VALUE[sid])
                    for sid in requested
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


# Per-slot font families the fake LLM hands back, matched to the demo
# fixture's font slot ids. Both families live in the fake catalog below.
_FAKE_FONT_FAMILY = {
    "display": "Funnel Display",
    "body": "Inter",
}

# Per-slot text values the fake LLM hands back, matched to the demo
# fixture's text slot ids. Each value sits well inside the slot's
# min/max bounds so the per-slot retry loop completes in one attempt.
_FAKE_TEXT_VALUE = {
    "booked_screen": "Locked in.",
    "cancel_cta": "Cancel",
    "home_greeting": "Welcome back, fighter.",
}


class _FakeGoogleFontsCatalog:
    """In-memory catalog: hands back a fixed pair of well-known families
    keyed under the lowercased name. Used by the FontSelectionService's
    membership check and its post-LLM family lookup."""

    def __init__(self) -> None:
        self._entries: dict[str, GoogleFontMetadata] = {
            "inter": GoogleFontMetadata(
                family="Inter",
                category="sans-serif",
                variants=["regular", "700"],
                files={
                    "regular": "https://fonts.gstatic.com/s/inter/regular.woff2",
                    "700": "https://fonts.gstatic.com/s/inter/700.woff2",
                },
            ),
            "funnel display": GoogleFontMetadata(
                family="Funnel Display",
                category="display",
                variants=["regular", "700"],
                files={
                    "regular": "https://fonts.gstatic.com/s/funneldisplay/regular.woff2",
                    "700": "https://fonts.gstatic.com/s/funneldisplay/700.woff2",
                },
            ),
        }

    async def contains(self, family: str) -> bool:
        return family.lower() in self._entries

    async def lookup(self, family: str) -> GoogleFontMetadata | None:
        return self._entries.get(family.lower())

    async def families(self) -> frozenset[str]:
        return frozenset(self._entries.keys())


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


def _patch_services(
    monkeypatch,
    color_slot_ids: list[str],
    font_slot_ids: list[str],
    text_slot_ids: list[str] | None = None,
) -> None:
    monkeypatch.setattr(
        orchestrator,
        "LiteLLMClient",
        lambda: _FakeLLM(color_slot_ids, font_slot_ids, text_slot_ids),
    )
    monkeypatch.setattr(
        orchestrator, "LiteLLMImageGenerator", lambda: _FakeImageGen()
    )
    monkeypatch.setattr(
        orchestrator, "PhotoRoomBackgroundRemover", lambda: _FakeBgRemover()
    )
    # The orchestrator constructs the catalog from settings — swap it out
    # for the in-memory fake so the run hits no network.
    monkeypatch.setattr(
        orchestrator,
        "HttpxGoogleFontsCatalog",
        lambda **_kwargs: _FakeGoogleFontsCatalog(),
    )


def test_pipeline_run_assembles_valid_output(tmp_path, monkeypatch):
    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
    )

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
    assert set(output.font_set.fonts) == {f.id for f in ctx.app.fonts}
    assert set(output.text_set.texts) == {t.id for t in ctx.app.texts}
    for slot_id, text in output.text_set.texts.items():
        assert text.value == _FAKE_TEXT_VALUE[slot_id]
    assert output.color_set.mode == ctx.cust.colors_direction.mode
    # Each font slot carries the LLM-picked family + the catalog-derived
    # category (the LLM never picks category — it's lifted from the
    # Google Fonts catalog entry post-validation).
    for slot_id, font in output.font_set.fonts.items():
        assert font.family == _FAKE_FONT_FAMILY[slot_id]
        assert font.category  # set from the fake catalog entry
        assert font.display_name and font.description
    # Every colour carries every format + the six deterministic
    # derivations, and the flat recommendation palette is populated.
    for color in output.color_set.colors.values():
        assert (
            color.color.oklch
            and color.color.hsl
            and color.color.rgb
            and color.color.hex
        )
        # Derivations is a typed Pydantic model — every field is required,
        # so successful validation proves the six derivations are present.
        # Touch each to also assert non-None.
        for deriv_name in ("second", "third", "card", "popup", "dark", "light"):
            assert getattr(color.derivations, deriv_name) is not None
    palette = output.color_set.palette
    # 4 base slots + (4 slots × 6 derivations = 24) + 3 shared = 31 keys.
    for slot in ctx.app.colors:
        assert slot.id in palette
        for deriv in ("second", "third", "card", "popup", "dark", "light"):
            assert f"{slot.id}_{deriv}" in palette
    assert {"card", "popup", "divider"}.issubset(palette.keys())
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
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
    )
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
    # Typed primitives unwrapped to plain strings in the YAML — and the
    # body of every colour is now a nested ColorValue (composition), with
    # the same shape repeating inside `derivations` and `palette`.
    raw = yaml.safe_load(out_yaml.read_text())
    assert raw["color_set"]["mode"] in ("light", "dark")
    # OKLCH / HSL / RGB are STRUCTURED on the wire (dict per channel);
    # only hex is a string.
    any_color = next(iter(raw["color_set"]["colors"].values()))
    assert set(any_color["color"]["oklch"].keys()) >= {"l", "c", "h"}
    assert set(any_color["color"]["hsl"].keys()) >= {"h", "s", "l"}
    assert set(any_color["color"]["rgb"].keys()) >= {"r", "g", "b"}
    assert isinstance(any_color["color"]["hex"], str)
    # Derivations are a dict of ColorValue-shaped entries with the exact
    # seven pipeline-computed keys.
    assert set(any_color["derivations"]) == {
        "second", "third", "card", "popup", "dark", "light", "regular_text",
    }
    second = any_color["derivations"]["second"]
    assert isinstance(second["oklch"], dict)
    assert isinstance(second["hex"], str)
    # The flat palette dict is also present and ColorValue-shaped.
    assert isinstance(raw["color_set"]["palette"], dict)
    any_palette_entry = next(iter(raw["color_set"]["palette"].values()))
    assert isinstance(any_palette_entry["oklch"], dict)
    assert isinstance(any_palette_entry["hex"], str)


def test_writer_writes_run_cost_breakdown(tmp_path, monkeypatch):
    """The writer sums each paid service's running cost into the optional
    ``RunCost`` (total + per-service + per-model-id breakdown) and it
    round-trips."""
    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
    )
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
    # The colour shape changed: a ColorOutput now nests its value as a
    # ColorValue and carries the six pipeline-computed derivations. Build
    # the fixture by running the node's deterministic assembly over a
    # hand-built LLMPalette so it stays contract-valid as the math
    # evolves.
    from schema import ColorMode
    from src.modules.colors.color_models import LLMSlotResponse, LLMPalette
    from tests.colour_helpers import assemble_color_palette

    roles = {
        "primary": None,
        "background": ColorRole.BACKGROUND,
        "text": ColorRole.TEXT,
    }
    schema = LLMPalette(
        mode=ColorMode.LIGHT,
        roles=roles,
        colors={
            "primary": LLMSlotResponse(
                oklch=OklchColor.from_css("oklch(70% 0.19 41)"),
                display_name="Cage Orange",
                description="Primary brand accent.",
            ),
            "background": LLMSlotResponse(
                oklch=OklchColor.from_css("oklch(88% 0.01 80)"),
                display_name="Bone",
                description="Canvas.",
            ),
            "text": LLMSlotResponse(
                oklch=OklchColor.from_css("oklch(20% 0.01 250)"),
                display_name="Ink",
                description="Body copy.",
            ),
        },
    )
    expanded = assemble_color_palette(schema)
    colors = {
        sid: c.model_dump(mode="json") for sid, c in expanded.colors.items()
    }
    palette = {
        k: v.model_dump(mode="json") for k, v in expanded.palette.items()
    }

    # Back-compat: no optional fields at all (mode + palette are required,
    # though — both are deliberate breaking-change requirements of the
    # current ColorPalette).
    old = Output.model_validate(
        {
            "app": "demo",
            "display_name": "Demo App",
            "image_set": {"images": {"hero": dict(base_image)}},
            "color_set": {
                "mode": "light", "colors": colors, "palette": palette,
            },
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
            "color_set": {
                "mode": "dark", "colors": colors, "palette": palette,
            },
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
