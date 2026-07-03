"""End-to-end executor tests plus the mandated schema round-trips."""

from __future__ import annotations

import asyncio
import importlib.util
from pathlib import Path
from types import ModuleType

import pytest
import yaml
from PIL import Image

_REPO_ROOT = Path(__file__).resolve().parents[1]


def _load_script(rel_path: str) -> ModuleType:
    """Import a standalone ``scripts/**/run.py`` by path for main()-testing."""
    path = _REPO_ROOT / rel_path
    spec = importlib.util.spec_from_file_location(
        rel_path.replace("/", "_").removesuffix(".py"), path
    )
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

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
from src.modules.icons.icon_models import LLMIconPrompt, LLMIconResponse
from src.modules.images.image_models import ImageComplexity, ImagePrompt
from src.modules.texts.text_models import LLMTextResponse
from src.shared.interfaces.google_fonts_catalog import GoogleFontMetadata
from src.shared.interfaces.icon_set_catalog import IconSetCatalogEntry

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
_FAKE_ICON_COST = 0.04

# Each fake's per-model-id split. Distinct keys per service so the
# writer's merge is unambiguous and each bucket sums back to its service
# total (model-id keying; the bg remover under its synthetic key).
_FAKE_LLM_BY_MODEL = {
    "anthropic/demo-prompt": _FAKE_LLM_COST * 0.75,
    "gemini/demo-classify": _FAKE_LLM_COST * 0.25,
}
_FAKE_IMAGE_BY_MODEL = {"openai/demo-image": _FAKE_IMAGE_COST}
_FAKE_BG_BY_MODEL = {"recraft_remove_bg": _FAKE_BG_COST}
_FAKE_ICON_BY_MODEL = {"recraftv4_1_utility_vector": _FAKE_ICON_COST}

# What the fake LLM matches each demo icon slot to: home_tab + search_action
# resolve within the fake set; celebration_badge has no honest match (None)
# and routes to the generation path.
_FAKE_ICON_MATCH: dict[str, str | None] = {
    "home_tab": "home",
    "search_action": "search",
    "celebration_badge": None,
}
_FAKE_ICON_SET_ID = "lucide_lite"
_FAKE_ICON_SET_NAME = "Lucide Lite"


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
        icon_slot_ids: list[str] | None = None,
    ) -> None:
        self._color_slot_ids = color_slot_ids
        self._font_slot_ids = font_slot_ids
        # Text + icon slots are optional on the fake the same way they are
        # on AppFormat: a run with no text/icon slots never builds the
        # corresponding node, so the fake never sees that schema.
        self._text_slot_ids = text_slot_ids or []
        self._icon_slot_ids = icon_slot_ids or []

    async def complete_structured(
        self, messages, *, schema, model=None
    ):
        if getattr(schema, "__name__", "") == "ColorPalette":
            # Per-request closed model: one field per requested slot id.
            # The wire shape per slot is the narrow LLMSlotResponse (the
            # LLM only emits oklch + prose; derivations, hsl, rgb, and the
            # flat palette are computed post-call by the derivation service).
            # Constructing the model runs the deterministic contract.
            # Iterate the schema's fields (not the full slot list) so a
            # partial regen — a scoped subset schema — is handled too.
            result = schema(
                **{
                    sid: LLMSlotResponse(
                        oklch=_palette_oklch(sid),
                        display_name=f"{sid} tone",
                        description="on-brand demo colour",
                    )
                    for sid in schema.model_fields
                }
            )
        elif getattr(schema, "__name__", "") == "FontSelection":
            # Per-request closed model for fonts: one LLMFontResponse per
            # font slot. Constructing the model runs the Google-Fonts
            # membership validator — the fake catalog below contains the
            # families we hand back here.
            # Iterate the schema's fields (not the full slot list) so a
            # partial regen — a scoped subset schema — is handled too.
            result = schema(
                **{
                    sid: LLMFontResponse(
                        family=_FAKE_FONT_FAMILY[sid],
                        display_name=f"{sid} pick",
                        description=f"on-brand demo font for {sid}",
                    )
                    for sid in schema.model_fields
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
        elif getattr(schema, "__name__", "") == "IconSetSelection":
            # Set selection (call 1): pick the one fake set. Constructing
            # the model runs the known-set-id validator (the fake catalog
            # below exposes exactly this id).
            result = schema(
                icon_set=_FAKE_ICON_SET_ID, reason="fits the demo brand"
            )
        elif getattr(schema, "__name__", "") == "IconMatch":
            # Matching (call 2): one LLMIconResponse per icon slot. Matched
            # slots resolve within the fake set; the unmatched slot returns
            # None and routes to generation. Constructing the model runs
            # the set-membership validator.
            requested = list(schema.model_fields)
            result = schema(
                **{
                    sid: LLMIconResponse(
                        icon=_FAKE_ICON_MATCH[sid],
                        match_reason="demo match"
                        if _FAKE_ICON_MATCH[sid]
                        else "nothing in the set fits",
                    )
                    for sid in requested
                }
            )
        elif getattr(schema, "__name__", "") == "IconPrompt":
            # Prompt authoring (call 3): one Recraft prompt per unmatched
            # slot the service asked about.
            requested = list(schema.model_fields)
            result = schema(
                **{
                    sid: LLMIconPrompt(
                        name=f"{sid}_icon",
                        prompt=f"a monochrome {sid} svg icon",
                    )
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

    async def edit(
        self,
        prompt: str,
        source: Path,
        dest: Path,
        *,
        model: str,
        quality: str | None = None,
    ) -> AbsolutePath:
        assert source.is_file()  # edit reads the current image
        dest.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGB", (64, 64), (20, 20, 20)).save(dest)
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


class _FakeIconSetCatalog:
    """In-memory icon set catalog: one set whose icons exist as real SVG
    files in a temp dir (so ``icon_path`` resolves to a copyable file).
    Used by the icon module's selection + matching + the node's copy."""

    def __init__(self) -> None:
        import tempfile

        self._icons = ["home", "search", "settings"]
        self._dir = Path(tempfile.mkdtemp())
        for name in self._icons:
            (self._dir / f"{name}.svg").write_text(
                "<svg xmlns='http://www.w3.org/2000/svg'/>", encoding="utf-8"
            )
        self._entry = IconSetCatalogEntry(
            id=_FAKE_ICON_SET_ID,
            name=_FAKE_ICON_SET_NAME,
            vibe="clean modern monochrome line icons",
            icons=self._icons,
        )

    async def sets(self) -> list[IconSetCatalogEntry]:
        return [self._entry]

    async def lookup(self, set_id: str) -> IconSetCatalogEntry | None:
        return self._entry if set_id == self._entry.id else None

    async def icon_path(
        self, set_id: str, icon_name: str
    ) -> AbsolutePath | None:
        if set_id != self._entry.id:
            return None
        p = self._dir / f"{icon_name}.svg"
        return AbsolutePath(str(p.resolve())) if p.is_file() else None


class _FakeIconGenerator:
    cost = _FAKE_ICON_COST
    cost_by_model = _FAKE_ICON_BY_MODEL

    async def generate(
        self,
        prompt: str,
        dest: Path,
        *,
        model: str,
        quality: str | None = None,
    ) -> AbsolutePath:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(
            "<svg xmlns='http://www.w3.org/2000/svg'><!-- generated --></svg>",
            encoding="utf-8",
        )
        return AbsolutePath(str(dest.resolve()))


def _patch_services(
    monkeypatch,
    color_slot_ids: list[str],
    font_slot_ids: list[str],
    text_slot_ids: list[str] | None = None,
    icon_slot_ids: list[str] | None = None,
) -> None:
    monkeypatch.setattr(
        orchestrator,
        "LiteLLMClient",
        lambda: _FakeLLM(
            color_slot_ids, font_slot_ids, text_slot_ids, icon_slot_ids
        ),
    )
    monkeypatch.setattr(
        orchestrator, "LiteLLMImageGenerator", lambda: _FakeImageGen()
    )
    monkeypatch.setattr(
        orchestrator, "RecraftBackgroundRemover", lambda: _FakeBgRemover()
    )
    monkeypatch.setattr(
        orchestrator, "RecraftIconGenerator", lambda: _FakeIconGenerator()
    )
    # The orchestrator constructs the catalogs from settings — swap them
    # out for the in-memory fakes so the run hits no network / no disk.
    monkeypatch.setattr(
        orchestrator,
        "HttpxGoogleFontsCatalog",
        lambda **_kwargs: _FakeGoogleFontsCatalog(),
    )
    monkeypatch.setattr(
        orchestrator,
        "LocalIconSetCatalog",
        lambda **_kwargs: _FakeIconSetCatalog(),
    )


def test_pipeline_run_assembles_valid_output(tmp_path, monkeypatch):
    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )

    result = asyncio.run(Pipeline().run(ctx))
    output = result.output

    assert isinstance(output, Output)
    # The run exposes its paid services so the writer can total cost.
    assert result.llm.cost == _FAKE_LLM_COST
    assert result.image_gen.cost == _FAKE_IMAGE_COST
    assert result.bg_remover.cost == _FAKE_BG_COST
    assert result.icon_gen.cost == _FAKE_ICON_COST
    assert output.app == ctx.app.id
    assert output.display_name == ctx.app.display_name
    # Every declared slot resolved.
    assert set(output.color_set.colors) == {c.id for c in ctx.app.colors}
    assert set(output.image_set.images) == {i.id for i in ctx.app.images}
    assert set(output.font_set.fonts) == {f.id for f in ctx.app.fonts}
    assert set(output.text_set.texts) == {t.id for t in ctx.app.texts}
    for slot_id, text in output.text_set.texts.items():
        assert text.value == _FAKE_TEXT_VALUE[slot_id]
    # Every icon slot resolved — matched slots carry the chosen set id,
    # the unmatched slot (no honest match) carries the "generated"
    # sentinel — and every SVG was written to this run's icons/ dir.
    assert set(output.icon_set.icons) == {i.id for i in ctx.app.icons}
    for slot_id, icon in output.icon_set.icons.items():
        assert icon.icon_key == slot_id
        p = Path(str(icon.path))
        assert p.is_absolute() and p.exists()
        assert p.name == f"{slot_id}.svg"
        # icon_set is the chosen set id for matched AND generated icons.
        assert icon.icon_set == _FAKE_ICON_SET_ID
        if _FAKE_ICON_MATCH[slot_id] is not None:
            # Matched: icon_name is the set icon's short-name; no prompt.
            assert icon.icon_name == _FAKE_ICON_MATCH[slot_id]
            assert icon.prompt is None
        else:
            # Generated: AI-authored icon_name + the Recraft prompt.
            assert icon.icon_name == f"{slot_id}_icon"
            assert icon.prompt
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
        [i.id for i in ctx.app.icons],
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
        [i.id for i in ctx.app.icons],
    )
    result = asyncio.run(Pipeline().run(ctx))

    Writer().write(result, ctx)

    raw = yaml.safe_load(ctx.output_path().read_text())
    cost = raw["cost"]
    assert cost["llm"] == pytest.approx(_FAKE_LLM_COST)
    assert cost["image_generation"] == pytest.approx(_FAKE_IMAGE_COST)
    assert cost["background_removal"] == pytest.approx(_FAKE_BG_COST)
    assert cost["icon_generation"] == pytest.approx(_FAKE_ICON_COST)
    assert cost["total"] == pytest.approx(
        _FAKE_LLM_COST + _FAKE_IMAGE_COST + _FAKE_BG_COST + _FAKE_ICON_COST
    )
    # Per-model-id breakdown: every service's buckets merged, keyed by
    # model id (the background remover under its synthetic key, the Recraft
    # icon generator under its model id), summing back to total.
    by_model = cost["by_model"]
    assert set(by_model) == (
        set(_FAKE_LLM_BY_MODEL)
        | set(_FAKE_IMAGE_BY_MODEL)
        | set(_FAKE_BG_BY_MODEL)
        | set(_FAKE_ICON_BY_MODEL)
    )
    assert "recraft_remove_bg" in by_model
    assert "recraftv4_1_utility_vector" in by_model
    # Each bucket is independently rounded to COST_PRECISION (6 dp), so the
    # per-model sum equals total only modulo that rounding (as the RunCost
    # docstring states) — a real double-count/miss would be off by cents.
    assert sum(by_model.values()) == pytest.approx(cost["total"], abs=1e-5)
    # Optional field validates back through the schema.
    reloaded = Output.model_validate(raw)
    assert reloaded.cost.total == pytest.approx(cost["total"])
    assert reloaded.cost.by_model == pytest.approx(by_model)


def test_run_with_full_seed_generates_nothing(tmp_path, monkeypatch):
    """A second pass seeded with a complete prior run runs no node and
    reassembles the identical Output (the expand no-op: no spend)."""
    from src.executor.seed import build_seed

    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    full = asyncio.run(Pipeline().run(ctx))
    seed = build_seed(ctx.app, full.output)

    again = asyncio.run(Pipeline().run(ctx, seed=seed))

    assert again.generated == frozenset()
    assert again.output == full.output


def test_run_with_seed_injects_done_dep_into_generated_node(
    tmp_path, monkeypatch
):
    """Seed everything except the image: the image node still runs and
    consumes the seeded colour palette as its input. If the seeded colour
    weren't injected, the image node's run() would fail on a missing dep —
    so a clean run proves the injection."""
    from src.executor.seed import build_seed

    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    full = asyncio.run(Pipeline().run(ctx))
    seed = {
        k: v for k, v in build_seed(ctx.app, full.output).items() if k != "hero"
    }

    res = asyncio.run(Pipeline().run(ctx, seed=seed))

    assert res.generated == frozenset({"hero"})
    assert "hero" in res.output.image_set.images


def test_font_partial_regen_preserves_siblings_and_steers(tmp_path, monkeypatch):
    """Reopen a done run and regenerate only the 'display' font with a spec:
    the font node re-runs, 'body' is kept verbatim, 'display' carries the
    steering, and no other slot regenerates."""
    from schema import OverwriteSpecs
    from src.executor.seed import build_seed

    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    full = asyncio.run(Pipeline().run(ctx))

    seed = build_seed(ctx.app, full.output)
    seed.pop("display")  # drop the target so it re-rolls
    ctx.overwrite_specs = OverwriteSpecs(specs="make it more elegant")
    res = asyncio.run(Pipeline().run(ctx, seed=seed))

    # Only the 'display' slot re-ran (slot-level).
    assert res.generated == frozenset({"display"})
    # 'body' (non-dirty) is the seeded object, verbatim.
    assert res.output.font_set.fonts["body"] == full.output.font_set.fonts["body"]
    # 'display' (dirty) carries the steering it was regenerated under.
    assert (
        res.output.font_set.fonts["display"].overwrite_specs.specs
        == "make it more elegant"
    )


def test_color_partial_regen_preserves_siblings_and_steers(
    tmp_path, monkeypatch
):
    """Regenerate only the 'primary' colour: the colour node re-runs but
    background/text/accent are kept verbatim and 'primary' carries the
    steering — the deterministic-preservation guarantee that keeps every
    image keyed to the untouched colours valid."""
    from schema import OverwriteSpecs
    from src.executor.seed import build_seed

    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    full = asyncio.run(Pipeline().run(ctx))

    seed = build_seed(ctx.app, full.output)
    seed.pop("primary")  # drop the target so it re-rolls
    ctx.overwrite_specs = OverwriteSpecs(specs="warmer")
    res = asyncio.run(Pipeline().run(ctx, seed=seed))

    assert res.generated == frozenset({"primary"})
    for sid in ("background", "text", "accent"):
        assert (
            res.output.color_set.colors[sid]
            == full.output.color_set.colors[sid]
        )
    assert (
        res.output.color_set.colors["primary"].overwrite_specs.specs
        == "warmer"
    )


def test_regen_script_regenerates_named_slot(tmp_path, monkeypatch):
    """The regen script reopens a run, re-makes one colour slot, preserves
    the rest, and appends a REGENERATE ledger entry with the steering."""
    _patch_services(
        monkeypatch,
        ["primary", "background", "text", "accent"],
        ["display", "body"],
        ["booked_screen", "cancel_cta", "home_greeting"],
        ["home_tab", "search_action", "celebration_badge"],
    )
    # Build a real run dir: <tmp>/demo/run1 with app/cust/output.yaml.
    ctx = RunContext(_run_ctx(tmp_path).app, _run_ctx(tmp_path).cust, tmp_path,
                     run_id="run1")
    full = asyncio.run(Pipeline().run(ctx))
    Writer().write(full, ctx)

    regen = _load_script("scripts/regen/run.py")
    rc = asyncio.run(
        regen.main(
            ["--run-dir", str(ctx.run_dir), "--slot", "primary",
             "--spec", "warmer"]
        )
    )
    assert rc == 0

    out = Output.model_validate(yaml.safe_load(ctx.output_path().read_text()))
    assert out.color_set.colors["primary"].overwrite_specs.specs == "warmer"
    assert out.color_set.colors["accent"] == full.output.color_set.colors[
        "accent"
    ]
    from schema import ExpansionCostLog, ExpansionKind

    ledger = ExpansionCostLog.model_validate(
        yaml.safe_load(ctx.expansion_cost_path().read_text())
    )
    assert ledger.expansions[-1].kind is ExpansionKind.REGENERATE
    assert ledger.expansions[-1].overwrite_specs.specs == "warmer"


def test_regen_script_rejects_image_slot(tmp_path, monkeypatch):
    """Image slots are out of scope for the generic regen script."""
    _patch_services(
        monkeypatch,
        ["primary", "background", "text", "accent"],
        ["display", "body"],
        ["booked_screen", "cancel_cta", "home_greeting"],
        ["home_tab", "search_action", "celebration_badge"],
    )
    ctx = RunContext(_run_ctx(tmp_path).app, _run_ctx(tmp_path).cust, tmp_path,
                     run_id="run1")
    full = asyncio.run(Pipeline().run(ctx))
    Writer().write(full, ctx)

    regen = _load_script("scripts/regen/run.py")
    image_id = ctx.app.images[0].id
    with pytest.raises(SystemExit, match="regen_image"):
        asyncio.run(
            regen.main(["--run-dir", str(ctx.run_dir), "--slot", image_id])
        )


def _full_run_dir(tmp_path, monkeypatch):
    """A real run dir (<tmp>/demo/run1) with output.yaml + a final image,
    produced by a full fake-service run, for the image regen tests."""
    base = _run_ctx(tmp_path)
    ctx = RunContext(base.app, base.cust, tmp_path, run_id="run1")
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    full = asyncio.run(Pipeline().run(ctx))
    Writer().write(full, ctx)
    return ctx


def test_regen_image_create_new_preserves_prior_numbered(tmp_path, monkeypatch):
    """regen_image --mode create_new regenerates just the image, keeps the
    prior as a numbered file in images/, and logs a REGENERATE entry."""
    from schema import ExpansionCostLog, ExpansionKind

    ctx = _full_run_dir(tmp_path, monkeypatch)
    image_id = ctx.app.images[0].id
    assert (ctx.run_dir / "final_images" / f"{image_id}.png").is_file()

    regen = _load_script("scripts/regen_image/run.py")
    rc = asyncio.run(
        regen.main(
            ["--run-dir", str(ctx.run_dir), "--slot", image_id,
             "--spec", "brighter", "--mode", "create_new"]
        )
    )
    assert rc == 0
    # Prior image kept (numbered) in images/ — no history in output.yaml.
    assert (ctx.run_dir / "images" / f"{image_id}.v1.png").is_file()

    out = Output.model_validate(yaml.safe_load(ctx.output_path().read_text()))
    assert out.image_set.images[image_id].overwrite_specs.specs == "brighter"
    ledger = ExpansionCostLog.model_validate(
        yaml.safe_load(ctx.expansion_cost_path().read_text())
    )
    assert ledger.expansions[-1].kind is ExpansionKind.REGENERATE
    assert ledger.expansions[-1].generated == [image_id]
    assert ledger.expansions[-1].overwrite_specs.image_to_image is None


def test_regen_image_edit_current_uses_edit_path(tmp_path, monkeypatch):
    """regen_image --mode edit_current_image edits the current image (records
    image_to_image on the stamped specs)."""
    ctx = _full_run_dir(tmp_path, monkeypatch)
    image_id = ctx.app.images[0].id

    regen = _load_script("scripts/regen_image/run.py")
    rc = asyncio.run(
        regen.main(
            ["--run-dir", str(ctx.run_dir), "--slot", image_id,
             "--spec", "darker background", "--mode", "edit_current_image"]
        )
    )
    assert rc == 0
    out = Output.model_validate(yaml.safe_load(ctx.output_path().read_text()))
    img = out.image_set.images[image_id]
    assert img.overwrite_specs.specs == "darker background"
    assert img.overwrite_specs.image_to_image is not None  # edit, not create


def test_edit_customization_targeted_edit(tmp_path):
    """edit_customization applies only the given flags, preserves the rest,
    and re-validates before writing."""
    import shutil

    src = APP_DIR / "customization.yaml"
    f = tmp_path / "customization.yaml"
    shutil.copy(src, f)
    original = Customization.model_validate(yaml.safe_load(src.read_text()))

    edit = _load_script("scripts/edit_customization/run.py")
    rc = edit.main(["--file", str(f), "--name", "New Name", "--mode", "dark"])
    assert rc == 0

    out = Customization.model_validate(yaml.safe_load(f.read_text()))
    assert out.design_direction.name == "New Name"  # changed
    assert out.colors_direction.mode.value == "dark"  # changed
    # An un-passed field is preserved verbatim.
    assert (
        out.design_direction.long_desc
        == original.design_direction.long_desc
    )


def test_edit_customization_missing_file_exits(tmp_path):
    """A missing file is a clean SystemExit, not a traceback."""
    edit = _load_script("scripts/edit_customization/run.py")
    with pytest.raises(SystemExit, match="no such file"):
        edit.main(["--file", str(tmp_path / "nope.yaml"), "--name", "X"])


def test_expand_with_updated_app_yaml_adds_slot(tmp_path, monkeypatch):
    """expand --app-yaml uses an UPDATED inventory (not the run's snapshot):
    a slot added to it is generated, the rest preserved, and the run dir's
    snapshot is refreshed to match."""
    ctx = _full_run_dir(tmp_path, monkeypatch)

    # Updated inventory: the live app.yaml plus one new image slot.
    app_data = yaml.safe_load((APP_DIR / "app.yaml").read_text())
    app_data["images"].append(
        {"id": "extra_hero", "description": "a second hero image"}
    )
    updated = tmp_path / "updated_app.yaml"
    updated.write_text(yaml.safe_dump(app_data))

    expand = _load_script("scripts/expand/run.py")
    rc = asyncio.run(
        expand.main(
            ["--run-dir", str(ctx.run_dir), "--app-yaml", str(updated)]
        )
    )
    assert rc == 0

    out = Output.model_validate(yaml.safe_load(ctx.output_path().read_text()))
    assert "extra_hero" in out.image_set.images  # new slot filled
    assert "hero" in out.image_set.images  # original preserved
    # The run dir's snapshot is refreshed to the inventory it now reflects.
    snap = AppFormat.model_validate(
        yaml.safe_load((ctx.run_dir / "app.yaml").read_text())
    )
    assert "extra_hero" in {s.id for s in snap.images}


def test_write_expansion_preserves_cost_and_appends_ledger(
    tmp_path, monkeypatch
):
    """write_expansion keeps output.yaml's original cost untouched and
    records this pass's spend + generated keys in expansion_cost.yaml."""
    from schema import ExpansionCostLog, ExpansionKind, OverwriteSpecs
    from src.executor.seed import build_seed

    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    # Full run + normal write so output.yaml carries the original cost.
    full = asyncio.run(Pipeline().run(ctx))
    Writer().write(full, ctx)
    original = Output.model_validate(
        yaml.safe_load(ctx.output_path().read_text())
    )
    assert original.cost is not None

    # Regenerate only the image (seed everything else).
    ctx.overwrite_specs = OverwriteSpecs(specs="darker background")
    seed = {
        k: v for k, v in build_seed(ctx.app, full.output).items() if k != "hero"
    }
    expanded = asyncio.run(Pipeline().run(ctx, seed=seed))
    Writer().write_expansion(
        expanded,
        ctx,
        original_cost=original.cost,
        original_category=original.category,
        kind=ExpansionKind.REGENERATE,
    )

    # output.yaml: cost block is the ORIGINAL, byte-for-byte.
    after = Output.model_validate(
        yaml.safe_load(ctx.output_path().read_text())
    )
    assert after.cost == original.cost

    # expansion_cost.yaml: one entry, this pass's kind + generated + spend.
    ledger = ExpansionCostLog.model_validate(
        yaml.safe_load(ctx.expansion_cost_path().read_text())
    )
    assert len(ledger.expansions) == 1
    entry = ledger.expansions[0]
    assert entry.kind is ExpansionKind.REGENERATE
    assert entry.generated == ["hero"]
    assert entry.overwrite_specs.specs == "darker background"
    assert entry.cost.image_generation == pytest.approx(_FAKE_IMAGE_COST)

    # A second pass appends rather than overwrites.
    Writer().write_expansion(
        expanded,
        ctx,
        original_cost=original.cost,
        original_category=original.category,
        kind=ExpansionKind.REGENERATE,
    )
    ledger2 = ExpansionCostLog.model_validate(
        yaml.safe_load(ctx.expansion_cost_path().read_text())
    )
    assert len(ledger2.expansions) == 2


def test_write_expansion_carries_category_forward(tmp_path, monkeypatch):
    """A regen/expand pass carries the run's (hand-stamped) category forward
    into the re-dumped output.yaml — the assembled Output has none, so without
    the carry-forward the theme would silently drop out of the picker."""
    from schema import ExpansionKind, OverwriteSpecs
    from src.executor.seed import build_seed

    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    full = asyncio.run(Pipeline().run(ctx))
    # Today's reality: a full run assembles category=None; the value is
    # stamped by hand afterwards. Simulate that by writing it with the stamp,
    # then reload the way the in-place scripts do (load_run → output.category).
    Writer().write(full, ctx, prior_category="minimalist")
    original = Output.model_validate(
        yaml.safe_load(ctx.output_path().read_text())
    )
    assert original.category == "minimalist"

    # Regenerate one image, threading the loaded category as the scripts do.
    ctx.overwrite_specs = OverwriteSpecs(specs="darker background")
    seed = {
        k: v for k, v in build_seed(ctx.app, full.output).items() if k != "hero"
    }
    expanded = asyncio.run(Pipeline().run(ctx, seed=seed))
    Writer().write_expansion(
        expanded,
        ctx,
        original_cost=original.cost,
        original_category=original.category,
        kind=ExpansionKind.REGENERATE,
    )

    after = Output.model_validate(
        yaml.safe_load(ctx.output_path().read_text())
    )
    assert after.category == "minimalist"


def test_full_rerun_captures_and_carries_category(tmp_path, monkeypatch):
    """The full in-place re-run seam: cli._existing_category reads the prior
    run's stamp before the pipeline clears output.yaml, and Writer.write
    re-stamps it — so a re-run keeps the theme categorised, while a fresh run
    (no prior file, prior_category=None) stays uncategorised."""
    import src.cli as cli

    ctx = _run_ctx(tmp_path)
    _patch_services(
        monkeypatch,
        [c.id for c in ctx.app.colors],
        [f.id for f in ctx.app.fonts],
        [t.id for t in ctx.app.texts],
        [i.id for i in ctx.app.icons],
    )
    result = asyncio.run(Pipeline().run(ctx))

    # No prior file → captured category is None (a fresh run stays None).
    assert cli._existing_category(ctx.output_path()) is None
    Writer().write(result, ctx)
    fresh = Output.model_validate(
        yaml.safe_load(ctx.output_path().read_text())
    )
    assert fresh.category is None

    # Hand-stamp the run, then take the full-re-run seam: capture the prior
    # stamp (as cli.main does before Pipeline.run clears the file), re-stamp it.
    Writer().write(result, ctx, prior_category="bold")
    captured = cli._existing_category(ctx.output_path())
    assert captured == "bold"
    Writer().write(result, ctx, prior_category=captured)
    after = Output.model_validate(
        yaml.safe_load(ctx.output_path().read_text())
    )
    assert after.category == "bold"


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
        "version": "0123456789ab",  # required: every image carries its token
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
            "design_name": "Demo App",
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
            "design_name": "Demo App",
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
