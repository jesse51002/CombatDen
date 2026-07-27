"""Light, mocked tests for the colour + image nodes (no network)."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest
from PIL import Image
from pydantic import ValidationError

from schema import (
    AppFormat,
    ColorMode,
    ColorPalette,
    ColorRole,
    Complexity,
    Customization,
    ImageOutput,
    OklchColor,
    OverwriteSpecs,
)
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.core.util import load_yaml
from src.modules.base import DependencyKind
from src.modules.categories.category_models import (
    CategoryOutput,
    build_category_selection_model,
)
from src.modules.categories.category_node import (
    CATEGORY_SLOT_ID,
    CategoryNode,
)
from src.modules.categories.category_selection_service import (
    CATEGORY_PROMPT_PATH,
    CategorySelectionService,
)
from src.modules.colors.color_models import LLMSlotResponse, build_color_response_model
from src.modules.colors.color_node import ColorNode
from src.modules.colors.color_models import LLMPalette
from src.modules.images.background_service import (
    BG_MAX_ATTEMPTS,
    BackgroundService,
)
from src.modules.icons.icon_models import (
    LLMIconPrompt,
    LLMIconResponse,
    build_icon_match_model,
)
from src.modules.icons.icon_node import IconNode
from src.shared.services.recraft_icon_generator import (
    RECRAFT_PRICE_USD,
    RecraftIconGenerator,
)
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_models import ImageComplexity, ImagePrompt
from src.modules.images.image_node import ImageNode
from schema import AbsolutePath
from src.shared.interfaces.icon_set_catalog import IconSetCatalogEntry

_COLOR = DependencyKind.COLOR.value

# Committed fixture tree — never the live ``apps/`` production runs.
_FIXTURE_APP = Path(__file__).resolve().parent / "data" / "apps" / "demo"
APP_YAML = _FIXTURE_APP / "app.yaml"
CUST_YAML = _FIXTURE_APP / "customization.yaml"


def _run_ctx(tmp_path: Path) -> RunContext:
    app = AppFormat.model_validate(load_yaml(APP_YAML))
    cust = Customization.model_validate(load_yaml(CUST_YAML))
    return RunContext(app, cust, tmp_path)


def _contract_oklch(role: ColorRole | None, dark_mode: bool) -> str:
    """An oklch value that satisfies the deterministic contract for ``role``."""
    if role is ColorRole.BACKGROUND:
        return "oklch(15% 0.012 40)" if dark_mode else "oklch(96% 0.006 250)"
    if role is ColorRole.TEXT:
        return "oklch(92% 0.01 80)" if dark_mode else "oklch(20% 0.01 250)"
    return "oklch(55% 0.15 25)"  # primary/accent — unconstrained


def _full_palette(ctx: RunContext) -> ColorPalette:
    """Build a contract-valid, fully expanded palette by running the
    production derivation service over a hand-built ``LLMPalette`` —
    image-node tests see exactly the shape ``ColorNode`` produces."""
    roles = {s.id: s.role for s in ctx.app.colors}
    schema = LLMPalette(
        mode=ColorMode.DARK,
        roles=roles,
        colors={
            s.id: LLMSlotResponse(
                oklch=OklchColor.from_css(_contract_oklch(roles[s.id], True)),
                display_name=f"{s.id} tone",
                description=f"{s.id} colour",
            )
            for s in ctx.app.colors
        },
    )
    from tests.colour_helpers import assemble_color_palette

    return assemble_color_palette(schema)


# --- stub interfaces -------------------------------------------------------


class StubLLM:
    """Stub LLMClient: structured dispatched by schema, text a fixed str.

    Mirrors the real client's contract closely enough for module tests:
    an ``ImagePrompt`` request is answered with ``_text`` as the prompt;
    everything else returns the configured preset.
    """

    def __init__(
        self,
        *,
        structured: Any = None,
        structured_seq: list[Any] | None = None,
        text: str = "a generated prompt",
        complexity: Complexity = Complexity.LOW,
    ) -> None:
        self._structured = structured
        self._structured_seq = structured_seq
        self._text = text
        self._complexity = complexity
        self.structured_calls: list[dict] = []

    async def complete(self, messages: list[dict], **kw: Any) -> dict:
        raise AssertionError("complete() not expected in these tests")

    async def complete_structured(
        self, messages: list[dict], *, schema: Any, **kw: Any
    ) -> Any:
        self.structured_calls.append(
            {"messages": messages, "schema": schema, **kw}
        )
        if schema is ImagePrompt:
            result: Any = ImagePrompt(prompt=self._text)
        elif schema is ImageComplexity:
            result = ImageComplexity(complexity=self._complexity)
        elif self._structured_seq is not None:
            result = self._structured_seq[
                min(
                    len(self.structured_calls) - 1,
                    len(self._structured_seq) - 1,
                )
            ]
        else:
            result = self._structured
        return result


class StubImageGen:
    """Stub ImageGenerator: writes a placeholder file for generate and
    records the call stream."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, Path]] = []

    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> Any:
        self.calls.append((prompt, dest))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"raw-image-bytes")
        return str(dest.resolve())


class StubBgRemover:
    """Stub BackgroundRemover: writes a real (mostly transparent) RGBA
    PNG cutout."""

    def __init__(self) -> None:
        self.calls: list[tuple[Path, Path]] = []

    async def remove(self, src: Path, dst: Path) -> None:
        self.calls.append((src, dst))
        dst.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(dst)


def _image_node(
    ctx: RunContext,
    llm: Any,
    slot: Any,
    *,
    image_gen: Any = None,
    remover: Any = None,
    deps: frozenset[str] = frozenset({_COLOR}),
) -> ImageNode:
    """Build one per-slot ImageNode with real classifier + background
    sub-services wired to the same stub llm (mirrors the registry).
    Declared dependencies are always reference (folded into the prompt
    by the stub llm's ImagePrompt answer). ``deps`` is the slot's
    dependency-key set (default: colour only); pass the declared
    ``depends_on`` ids too for a slot that builds on others."""
    return ImageNode(
        ctx,
        slot=slot,
        deps=deps,
        llm=llm,
        image_gen=image_gen if image_gen is not None else StubImageGen(),
        classifier=ComplexityClassifier(llm=llm),
        background=BackgroundService(
            bg_remover=remover if remover is not None else StubBgRemover(),
        ),
    )


def _resolve(node: ImageNode, palette: ColorPalette) -> Any:
    """Inject the colour dependency the way the executor does, then run."""
    node.inputs = {_COLOR: palette}
    return asyncio.run(node.run())


# --- ColorNode -------------------------------------------------------------


def test_color_node_run_returns_full_palette(tmp_path: Path) -> None:
    ctx = _run_ctx(tmp_path)
    slot_ids = [slot.id for slot in ctx.app.colors]
    roles = {slot.id: slot.role for slot in ctx.app.colors}
    dark_mode = ctx.cust.colors_direction.mode is ColorMode.DARK
    # The LLM answers with an instance of the per-request closed model;
    # constructing it runs the deterministic contract after-validator, so
    # the stubbed palette must satisfy it.
    response_model = build_color_response_model(
        slot_ids, roles=roles, dark_mode=dark_mode
    )
    resolved = response_model(
        **{
            sid: LLMSlotResponse(
                # OklchColor is structured now — parse the CSS fixture
                # via from_css for readability.
                oklch=OklchColor.from_css(_contract_oklch(roles[sid], dark_mode)),
                display_name=f"{sid} tone",
                description=f"{sid} colour",
            )
            for sid in slot_ids
        }
    )
    llm = StubLLM(structured=resolved)
    node = ColorNode(ctx, llm=llm)

    result = asyncio.run(node.run())

    # run() flattens the closed model back into a ColorPalette map,
    # expands every slot into a full ColorOutput, and assembles the flat
    # recommendation palette.
    assert isinstance(result, ColorPalette)
    assert result.mode == ctx.cust.colors_direction.mode
    assert set(result.colors) == set(slot_ids)
    # Every colour carries every format + the six derivations, and the
    # flat palette has every slot's six derivation entries + the three
    # shared surfaces + the base slots. Derivations is a typed Pydantic
    # model — required-field validation proves the six exist; touch each
    # to also assert non-None.
    for color in result.colors.values():
        assert (
            color.color.oklch
            and color.color.hsl
            and color.color.rgb
            and color.color.hex
        )
        for deriv_name in ("second", "third", "card", "popup", "dark", "light"):
            assert getattr(color.derivations, deriv_name) is not None
    for sid in slot_ids:
        for deriv in ("second", "third", "card", "popup", "dark", "light"):
            assert f"{sid}_{deriv}" in result.palette
    assert {"card", "popup", "divider"}.issubset(result.palette.keys())
    # Exactly one structured call.
    assert len(llm.structured_calls) == 1
    # The colour node is the DAG root: keyed "color", no dependencies.
    assert node.key == _COLOR
    assert node.deps == frozenset()


def test_color_node_clamps_out_of_band_background(tmp_path: Path) -> None:
    """The contract no longer raises on background lightness; ColorNode
    clamps it deterministically so the client keeps elevation headroom."""
    ctx = _run_ctx(tmp_path)  # demo fixture is dark mode
    slot_ids = [slot.id for slot in ctx.app.colors]
    roles = {slot.id: slot.role for slot in ctx.app.colors}
    response_model = build_color_response_model(
        slot_ids, roles=roles, dark_mode=True
    )
    resolved = response_model(
        **{
            sid: LLMSlotResponse(
                oklch=OklchColor.from_css(
                    "oklch(2% 0.006 40)"  # near pure black: valid, out of band
                    if roles[sid] is ColorRole.BACKGROUND
                    else _contract_oklch(roles[sid], True)
                ),
                display_name=f"{sid} tone",
                description=f"{sid} colour",
            )
            for sid in slot_ids
        }
    )
    node = ColorNode(ctx, llm=StubLLM(structured=resolved))

    result = asyncio.run(node.run())

    bg_id = next(s for s, r in roles.items() if r is ColorRole.BACKGROUND)
    # 0.02 lifted to the 0.08 dark-mode floor; chroma/hue preserved. The
    # base value lives under .color now (composition).
    assert str(result.colors[bg_id].color.oklch) == "oklch(8% 0.006 40)"


def test_color_response_model_rejects_missing_slot() -> None:
    """Completeness is structural: the per-slot model is required-only, so a
    payload missing a slot fails validation (re-asked by the client loop).

    The roles map now requires exactly one bg + one text at build time
    (the contract validator closure needs both), so the test uses a
    contract-shaped roles dict and omits one slot from the payload."""
    model = build_color_response_model(
        ["primary", "background", "text"],
        roles={
            "primary": None,
            "background": ColorRole.BACKGROUND,
            "text": ColorRole.TEXT,
        },
        dark_mode=True,
    )
    # Payload missing "background".
    missing_bg = (
        '{"primary": {"oklch": {"l": 0.55, "c": 0.15, "h": 25}, '
        '"display_name": "P", "description": "p"}, '
        '"text": {"oklch": {"l": 0.92, "c": 0.01, "h": 80}, '
        '"display_name": "T", "description": "t"}}'
    )

    with pytest.raises(ValidationError) as exc:
        model.model_validate_json(missing_bg)

    # The omitted slot is the reported missing field.
    assert "background" in str(exc.value)


def test_color_prompt_is_data_driven(tmp_path: Path) -> None:
    ctx = _run_ctx(tmp_path)

    # Prompt building moved into ColorSchemeService when the colour
    # pipeline split into schema → correction → derivation services —
    # the node is now a thin orchestrator with no prompt logic of its
    # own. Test the schema service's prompt builder directly.
    from src.modules.colors.color_scheme_service import (
        COLOR_PROMPT_PATH,
        ColorSchemeService,
    )

    prompt = ColorSchemeService._build_prompt(
        ctx,
        target_ids=[slot.id for slot in ctx.app.colors],
        fixed={},
    )
    template = COLOR_PROMPT_PATH.read_text(encoding="utf-8")

    # The .md template is app-agnostic: slots are deferred to a placeholder,
    # no slot description from app.yaml is baked into the file.
    assert "$slots" in template
    for slot in ctx.app.colors:
        assert slot.description not in template
    # The rule portion (before the brand-brief marker) holds no placeholders,
    # so it survives substitution byte-for-byte into the one prompt.
    rule_part = template.split("--- Brand brief ---")[0]
    assert rule_part in prompt
    # Brand data and every requested slot are substituted into that one prompt.
    assert ctx.cust.design_direction.name in prompt
    assert ctx.cust.colors_direction.description.strip() in prompt
    for slot in ctx.app.colors:
        assert f"- {slot.id}: {slot.description}" in prompt


# --- ImageNode -------------------------------------------------------------


def test_image_resolve_slot_falls_back_to_raw_when_no_cutout(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """Only when the remover never produced *any* cutout do we ship the
    un-removed raw image (autocrop skipped)."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    class FailingBgRemover:
        def __init__(self) -> None:
            self.calls: list[tuple[Path, Path]] = []

        async def remove(self, src: Path, dst: Path) -> None:
            self.calls.append((src, dst))
            raise ProviderError("remover down")

    llm = StubLLM(text="prompt for the subject")
    gen = StubImageGen()
    remover = FailingBgRemover()
    node = _image_node(ctx, llm, slot, image_gen=gen, remover=remover)

    autocrop_calls: list[Any] = []

    async def _spy_autocrop(self: Any, src: Path, dst: Path) -> None:
        autocrop_calls.append((src, dst))

    monkeypatch.setattr(BackgroundService, "_autocrop", _spy_autocrop)

    out = _resolve(node, palette)

    expected_path = str(ctx.image_path(slot.id))
    assert str(out.path) == expected_path
    # No cutout ever produced: raw copied to final, autocrop NOT called.
    assert autocrop_calls == []
    assert Path(expected_path).read_bytes() == b"raw-image-bytes"
    # Remover retried up to the cap (every attempt raised).
    assert len(remover.calls) == BG_MAX_ATTEMPTS


def test_image_resolve_slot_happy_path_autocrops(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM()
    gen = StubImageGen()
    remover = StubBgRemover()
    node = _image_node(ctx, llm, slot, image_gen=gen, remover=remover)

    autocrop_calls: list[tuple[Path, Path]] = []

    async def _spy_autocrop(self: Any, src: Path, dst: Path) -> None:
        autocrop_calls.append((src, dst))
        Path(dst).write_bytes(b"cropped")

    monkeypatch.setattr(BackgroundService, "_autocrop", _spy_autocrop)

    out = _resolve(node, palette)

    expected_path = str(ctx.image_path(slot.id))
    assert str(out.path) == expected_path
    # Happy path: autocrop invoked exactly once, dst is the final path.
    assert len(autocrop_calls) == 1
    assert str(autocrop_calls[0][1]) == expected_path
    assert Path(expected_path).read_bytes() == b"cropped"
    assert len(remover.calls) == 1


# --- BackgroundService crop passes -----------------------------------------
#
# The two-pass crop (alpha bbox -> grid halo trim -> alpha bbox) lives on
# BackgroundService. These exercise the deterministic crop directly via a
# throwaway service instance (the remover is unused on this path).


def _bg() -> BackgroundService:
    return BackgroundService(bg_remover=StubBgRemover())


def test_grid_trim_crops_tight_to_subject(tmp_path: Path) -> None:
    src = tmp_path / "src.png"
    dst = tmp_path / "dst.png"

    canvas = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    # Opaque rectangle off-centre: x in [10, 30), y in [60, 80).
    for x in range(10, 30):
        for y in range(60, 80):
            canvas.putpixel((x, y), (255, 0, 0, 255))
    canvas.save(src)

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    assert out.size == (20, 20)
    assert out.convert("RGBA").getbbox() == (0, 0, 20, 20)


def test_grid_trim_trims_halo_tighter_than_alpha_bbox(
    tmp_path: Path,
) -> None:
    src = tmp_path / "src.png"
    dst = tmp_path / "dst.png"

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

    # The plain alpha bbox is held loose by the faint corner smudge.
    loose = Image.open(src).convert("RGBA").getbbox()
    assert loose == (0, 0, 96, 96)

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    # The grid pass drops the all-halo border cells -> tight to subject.
    assert out.size == (32, 32)
    assert out.convert("RGBA").getbbox() == (0, 0, 32, 32)
    lw, lh = loose[2] - loose[0], loose[3] - loose[1]
    assert out.size[0] * out.size[1] < lw * lh


def test_grid_trim_opaque_is_noop(tmp_path: Path) -> None:
    src = tmp_path / "opaque.png"
    dst = tmp_path / "opaque_out.png"
    Image.new("RGBA", (64, 64), (10, 20, 30, 255)).save(src)

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    # No halo -> no red cells -> nothing trimmed, same extent.
    assert out.size == (64, 64)
    assert out.convert("RGBA").getbbox() == (0, 0, 64, 64)


def test_grid_trim_fully_transparent_copied(tmp_path: Path) -> None:
    src = tmp_path / "blank.png"
    dst = tmp_path / "blank_out.png"
    Image.new("RGBA", (20, 30), (0, 0, 0, 0)).save(src)

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    assert out.size == (20, 30)
    assert out.convert("RGBA").getbbox() is None


def test_grid_trim_all_red_keeps_bbox_unchanged(tmp_path: Path) -> None:
    src = tmp_path / "faint.png"
    dst = tmp_path / "faint_out.png"
    # Uniform faint alpha: getbbox() is non-empty (alpha>0) but every grid
    # cell is pure halo -> keep the alpha-bbox crop, never a zero-size image.
    Image.new("RGBA", (50, 50), (0, 0, 0, 8)).save(src)

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    assert out.size == (50, 50)


def test_grid_trim_partial_edge_cells(tmp_path: Path) -> None:
    src = tmp_path / "partial.png"
    dst = tmp_path / "partial_out.png"

    # 100 is not divisible by the 32px cell -> the last column/row is a
    # 4px partial cell. The subject runs to the very edge through it.
    canvas = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    # Faint smudge in the opposite corner cell, holding the alpha bbox
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

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    # Tight to the 60x60 subject: proves the surviving box uses the
    # clamped partial-cell extent (==100), not col*GRID_CELL_PX (==96).
    assert out.size == (60, 60)
    assert out.convert("RGBA").getbbox() == (0, 0, 60, 60)


def test_grid_trim_keeps_interior_hole(tmp_path: Path) -> None:
    src = tmp_path / "hole.png"
    dst = tmp_path / "hole_out.png"
    canvas = Image.new("RGBA", (96, 96), (10, 20, 30, 255))
    # A faint interior cell, fully surrounded by opaque subject. A
    # rectangular crop cannot carve it out -> the extent is preserved.
    for x in range(32, 64):
        for y in range(32, 64):
            canvas.putpixel((x, y), (0, 0, 0, 8))
    canvas.save(src)

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    assert out.size == (96, 96)


def test_grid_trim_smaller_than_one_cell(tmp_path: Path) -> None:
    src = tmp_path / "tiny.png"
    dst = tmp_path / "tiny_out.png"
    Image.new("RGBA", (16, 16), (200, 50, 50, 255)).save(src)

    _bg()._grid_trim_crop(src, dst)

    out = Image.open(dst)
    assert out.size == (16, 16)
    assert out.convert("RGBA").getbbox() == (0, 0, 16, 16)


def test_image_prompt_is_app_agnostic_and_theme_fixed(
    tmp_path: Path,
) -> None:
    """The rule file hardcodes no house style, and the built prompt names
    the flat background by the app's light/dark theme."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    from src.modules.images.image_node import (
        IMAGE_PROMPT_PATH,
        THEME_BG_DARK,
        THEME_BG_LIGHT,
    )

    template = IMAGE_PROMPT_PATH.read_text(encoding="utf-8")
    # The rule portion carries no app-specific aesthetic.
    rule_part = template.split("--- Brand brief ---")[0].lower()
    for banned in ("orange", "neon", "combat"):
        assert banned not in rule_part
    # Subject + background are deferred to placeholders, never baked in.
    assert "$subject" in template
    assert "$theme_background" in template
    for s in ctx.app.images:
        assert s.description not in template

    def _sent_prompt(dark_mode: bool) -> str:
        ctx.cust.colors_direction.mode = (
            ColorMode.DARK if dark_mode else ColorMode.LIGHT
        )
        llm = StubLLM(text="stub")
        node = _image_node(ctx, llm, slot)
        asyncio.run(node._build_prompt(palette, {}))
        return llm.structured_calls[0]["messages"][0]["content"]

    dark = _sent_prompt(True)
    light = _sent_prompt(False)

    for sent in (dark, light):
        # Every placeholder substituted into the one prompt.
        assert "$theme_background" not in sent
        assert "$subject" not in sent
        assert slot.description in sent
        assert ctx.cust.design_direction.name in sent
    # Background tracks the theme, named literally for the image model.
    assert THEME_BG_DARK in dark and THEME_BG_LIGHT not in dark
    assert THEME_BG_LIGHT in light and THEME_BG_DARK not in light


def test_image_prompt_injects_reopen_spec_as_override(tmp_path: Path) -> None:
    """A reopen-time ``--spec`` is folded into the create-new prompt as a
    high-priority override block. Regression: the spec used to be recorded but
    never reached ``_build_prompt``, so "make it a flame" was silently ignored
    and the model free-picked from the subject's example imagery."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    def _sent() -> str:
        llm = StubLLM(text="stub")
        asyncio.run(_image_node(ctx, llm, slot)._build_prompt(palette, {}))
        return llm.structured_calls[0]["messages"][0]["content"]

    # No spec (the default empty steering) → no override block, placeholder
    # substituted away to nothing.
    plain = _sent()
    assert "$override" not in plain
    assert "USER OVERRIDE" not in plain

    # With a spec → the override frame AND the verbatim spec reach the model.
    spec = "A stylized flame — not a yoga mat, not chevrons."
    ctx.overwrite_specs = OverwriteSpecs(specs=spec)
    sent = _sent()
    assert "$override" not in sent  # placeholder fully substituted
    assert "USER OVERRIDE" in sent
    assert spec in sent


def test_image_generation_retry_preserves_prior_attempt(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A generation attempt that writes a file then fails is moved aside
    under its attempt number instead of being clobbered by the retry; the
    canonical ``{slot}.raw.png`` still holds the winning attempt."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    class FlakyImageGen:
        """Writes a file then raises on the first call; succeeds next."""

        def __init__(self) -> None:
            self.n = 0

        async def generate(
            self, prompt: str, dest: Path, *, model: str, quality: str
        ) -> Any:
            self.n += 1
            dest.parent.mkdir(parents=True, exist_ok=True)
            if self.n == 1:
                dest.write_bytes(b"attempt-1-bytes")
                raise ProviderError("flaky generation")
            dest.write_bytes(b"attempt-2-bytes")
            return str(dest.resolve())

    gen = FlakyImageGen()
    node = _image_node(
        ctx, StubLLM(), slot, image_gen=gen, remover=StubBgRemover()
    )

    async def _spy_autocrop(self: Any, src: Path, dst: Path) -> None:
        Path(dst).write_bytes(b"cropped")

    monkeypatch.setattr(BackgroundService, "_autocrop", _spy_autocrop)

    _resolve(node, palette)

    assert gen.n == 2  # one failed attempt, one success
    canonical = ctx.image_dir / f"{slot.id}.raw.png"
    preserved = ctx.image_dir / f"{slot.id}.raw.attempt1.png"
    assert canonical.read_bytes() == b"attempt-2-bytes"
    assert preserved.read_bytes() == b"attempt-1-bytes"


def test_background_removal_retry_preserves_prior_cutout(
    tmp_path: Path,
) -> None:
    """A cutout an attempt wrote before failing is moved aside under its
    attempt number; the canonical cutout holds the winning attempt."""

    class FlakyRemover:
        """Writes a real cutout then raises on the first call; succeeds
        next, at a distinguishable size."""

        def __init__(self) -> None:
            self.calls = 0

        async def remove(self, src: Path, dst: Path) -> None:
            self.calls += 1
            dst.parent.mkdir(parents=True, exist_ok=True)
            if self.calls == 1:
                Image.new("RGBA", (8, 8), (0, 0, 0, 0)).save(dst)
                raise ProviderError("flaky remover")
            Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(dst)

    raw = tmp_path / "slotx.raw.png"
    Image.new("RGBA", (4, 4), (0, 0, 0, 0)).save(raw)
    dest = tmp_path / "final" / "slotx.png"

    remover = FlakyRemover()
    ok = asyncio.run(BackgroundService(bg_remover=remover).run(raw, dest))

    assert ok is True
    assert remover.calls == 2  # one failed attempt, one success
    canonical = tmp_path / "slotx.raw.cutout.png"
    preserved = tmp_path / "slotx.raw.cutout.attempt1.png"
    assert Image.open(canonical).size == (16, 16)  # winning attempt
    assert Image.open(preserved).size == (8, 8)  # the preserved one


# --- ImageNode with image dependencies (depends_on) ------------------------

_DEP_CUST = {
    "design_direction": {
        "name": "Demo",
        "short_desc": "short",
        "long_desc": "long",
    },
    "colors_direction": {"description": "calm", "mode": "dark"},
}
_DEP_COLORS = [
    {"id": "primary", "description": "primary"},
    {"id": "background", "description": "bg", "role": "background"},
    {"id": "text", "description": "text", "role": "text"},
    {"id": "accent", "description": "accent"},
]
_DEP_FONTS = [
    {"id": "display", "description": "headlines"},
    {"id": "body", "description": "body copy"},
]


def _dep_ctx(tmp_path: Path) -> RunContext:
    """A two-image app where ``derived`` declares ``depends_on: [hero]``."""
    app = AppFormat.model_validate(
        {
            "id": "demo",
            "display_name": "Demo",
            "images": [
                {"id": "hero", "description": "a hero"},
                {
                    "id": "derived",
                    "description": "builds on hero",
                    "depends_on": ["hero"],
                },
            ],
            "colors": _DEP_COLORS,
            "fonts": _DEP_FONTS,
        }
    )
    cust = Customization.model_validate(_DEP_CUST)
    return RunContext(app, cust, tmp_path)


def _run_derived(
    node: ImageNode, palette: ColorPalette, hero: ImageOutput
) -> Any:
    """Inject colour + the resolved ``hero`` dependency, then run."""
    node.inputs = {_COLOR: palette, "hero": hero}
    return asyncio.run(node.run())


def test_image_dependency_folds_into_prompt_as_reference(
    tmp_path: Path,
) -> None:
    """A declared dependency is always reference: its prompt is listed in
    the injected continuity block and generation stays text-to-image —
    the dependency image is never fed in."""
    ctx = _dep_ctx(tmp_path)
    palette = _full_palette(ctx)
    derived = ctx.app.images[1]
    hero = ImageOutput(
        path=ctx.image_path("hero"),
        version="0123456789ab",
        prompt="hero prompt",
    )

    llm = StubLLM()
    gen = StubImageGen()
    node = _image_node(
        ctx, llm, derived, image_gen=gen, deps=frozenset({_COLOR, "hero"})
    )

    out = _run_derived(node, palette, hero)

    sent = llm.structured_calls[0]["messages"][0]["content"]
    assert "Related assets (visual continuity)" in sent
    assert "hero: hero prompt" in sent
    # Text-to-image only — exactly one generate call, nothing fed in.
    assert len(gen.calls) == 1
    # The removed provenance/usage field is gone from the output model.
    assert not hasattr(out, "dependency_usage")
    assert out.prompt and out.complexity is not None


def test_image_no_dependency_block_absent(tmp_path: Path) -> None:
    """A slot with no image dependencies: nothing about dependencies
    reaches the model and the placeholder is fully substituted away."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM()
    node = _image_node(ctx, llm, slot)
    out = _resolve(node, palette)

    sent = llm.structured_calls[0]["messages"][0]["content"]
    assert "Related assets (visual continuity)" not in sent
    assert "$related_assets" not in sent
    assert not hasattr(out, "dependency_usage")


# --- FontNode --------------------------------------------------------------


def _fake_catalog():
    """Tiny in-memory catalog with two well-known families."""
    from schema import FontSet  # noqa: F401  (touch import to fail fast)
    from src.shared.interfaces.google_fonts_catalog import GoogleFontMetadata

    class _C:
        def __init__(self) -> None:
            self._e = {
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
                    variants=["regular"],
                    files={
                        "regular": "https://fonts.gstatic.com/s/funneldisplay/regular.woff2",
                    },
                ),
            }

        async def contains(self, family: str) -> bool:
            return family.lower() in self._e

        async def lookup(self, family: str):
            return self._e.get(family.lower())

        async def families(self) -> frozenset[str]:
            return frozenset(self._e.keys())

    return _C()


def test_font_node_run_returns_fontset_keyed_by_slot(tmp_path: Path) -> None:
    """FontNode resolves every slot, lifts each pick into a FontOutput
    with the catalog-supplied canonical family and category."""
    from schema import FontSet
    from src.modules.fonts.font_models import (
        LLMFontResponse,
        build_font_response_model,
    )
    from src.modules.fonts.font_node import FontNode

    ctx = _run_ctx(tmp_path)
    catalog = _fake_catalog()
    slot_ids = [s.id for s in ctx.app.fonts]
    known = asyncio.run(catalog.families())
    response_model = build_font_response_model(slot_ids, known_families=known)
    resolved = response_model(
        **{
            sid: LLMFontResponse(
                family="Funnel Display" if sid == "display" else "Inter",
                display_name=f"{sid} pick",
                description=f"on-brand demo font for {sid}",
            )
            for sid in slot_ids
        }
    )
    llm = StubLLM(structured=resolved)
    node = FontNode(ctx, llm=llm, catalog=catalog)

    out = asyncio.run(node.run())

    assert isinstance(out, FontSet)
    assert set(out.fonts) == set(slot_ids)
    # Family + category come from the catalog (not the LLM); the LLM
    # only picks the family + prose.
    assert out.fonts["display"].family == "Funnel Display"
    assert out.fonts["display"].category == "display"
    assert out.fonts["body" if "body" in slot_ids else slot_ids[-1]].family == "Inter"
    # FontNode is a level-0 sibling of the colour root.
    assert node.key == DependencyKind.FONT.value
    assert node.deps == frozenset()


def test_font_response_model_rejects_unknown_family() -> None:
    """The per-request response model's after-validator raises
    ValidationError when any picked family isn't in the catalog
    snapshot — exactly what makes the existing complete_structured
    retry loop re-ask the LLM, with no new retry code."""
    from src.modules.fonts.font_models import (
        LLMFontResponse,
        build_font_response_model,
    )

    model = build_font_response_model(
        ["display", "body"],
        known_families=frozenset({"inter", "funnel display"}),
    )
    with pytest.raises(ValidationError) as exc:
        model(
            display=LLMFontResponse(
                family="Definitely Not A Google Font",
                display_name="x",
                description="x",
            ),
            body=LLMFontResponse(
                family="Inter",
                display_name="x",
                description="x",
            ),
        )
    assert "Not found on Google Fonts" in str(exc.value)
    assert "display" in str(exc.value)


def test_font_prompt_is_data_driven(tmp_path: Path) -> None:
    """The .md template is app-agnostic — no slot description, no
    brand name baked in. The built prompt substitutes brand brief
    fields + every requested font slot's description."""
    from src.modules.fonts.font_selection_service import (
        FONT_PROMPT_PATH,
        FontSelectionService,
    )

    ctx = _run_ctx(tmp_path)
    prompt = FontSelectionService._build_prompt(
        ctx,
        target_ids=[slot.id for slot in ctx.app.fonts],
        fixed={},
    )
    template = FONT_PROMPT_PATH.read_text(encoding="utf-8")

    # Slots are deferred to a placeholder; no slot description baked in.
    assert "$slots" in template
    for slot in ctx.app.fonts:
        assert slot.description not in template
    # The rule portion (before the brand-brief marker) holds no
    # placeholders, so it survives substitution byte-for-byte.
    rule_part = template.split("--- Brand brief ---")[0]
    assert rule_part in prompt
    # Brand data + every requested slot substituted into the one prompt.
    assert ctx.cust.design_direction.name in prompt
    for slot in ctx.app.fonts:
        assert f"- {slot.id}: {slot.description}" in prompt


# --- icon node ------------------------------------------------------------


class _IconStubLLM:
    """Stub LLMClient for the icon node: dispatches the three icon
    schemas by ``__name__`` and records which calls were made."""

    cost = 0.0
    cost_by_model: dict[str, float] = {}

    def __init__(
        self, *, chosen_set: str, matches: dict[str, str | None]
    ) -> None:
        self._chosen = chosen_set
        self._matches = matches
        self.calls: list[str] = []

    async def complete(self, *a: Any, **k: Any) -> Any:
        raise AssertionError("complete() not expected in these tests")

    async def complete_structured(
        self, messages: list[dict], *, schema: Any, **kw: Any
    ) -> Any:
        name = getattr(schema, "__name__", "")
        self.calls.append(name)
        if name == "IconSetSelection":
            return schema(icon_set=self._chosen, reason="best fit")
        if name == "IconMatch":
            return schema(
                **{
                    sid: LLMIconResponse(
                        icon=self._matches[sid], match_reason="m"
                    )
                    for sid in schema.model_fields
                }
            )
        if name == "IconPrompt":
            return schema(
                **{
                    sid: LLMIconPrompt(name=f"{sid}_icon", prompt=f"a {sid} icon")
                    for sid in schema.model_fields
                }
            )
        raise AssertionError(f"unexpected schema {name!r}")


class _IconStubCatalog:
    """In-memory catalog: one set whose listed icons exist on disk (minus
    any explicitly withheld via ``on_disk``, to exercise the copy-miss
    fail-soft path)."""

    def __init__(
        self,
        tmp_path: Path,
        icons: list[str],
        *,
        on_disk: list[str] | None = None,
        license: str | None = None,
        attribution: str | None = None,
    ) -> None:
        self._entry = IconSetCatalogEntry(
            id="set_a",
            name="Set A",
            vibe="clean",
            icons=icons,
            license=license,
            attribution=attribution,
        )
        self._dir = tmp_path / "iconsrc"
        self._dir.mkdir(parents=True, exist_ok=True)
        for n in on_disk if on_disk is not None else icons:
            (self._dir / f"{n}.svg").write_text("<svg/>", encoding="utf-8")

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


class _IconStubGen:
    cost = 0.0
    cost_by_model: dict[str, float] = {}

    def __init__(self) -> None:
        self.calls: list[tuple[str, Path]] = []

    async def generate(
        self,
        prompt: str,
        dest: Path,
        *,
        model: str,
        quality: str | None = None,
    ) -> AbsolutePath:
        self.calls.append((prompt, dest))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text("<svg/>", encoding="utf-8")
        return AbsolutePath(str(dest.resolve()))


def _icon_node(
    ctx: RunContext,
    *,
    matches: dict[str, str | None],
    catalog_icons: list[str],
    on_disk: list[str] | None = None,
    license: str | None = None,
    attribution: str | None = None,
) -> tuple[IconNode, _IconStubLLM, _IconStubGen]:
    llm = _IconStubLLM(chosen_set="set_a", matches=matches)
    gen = _IconStubGen()
    catalog = _IconStubCatalog(
        ctx.run_dir,
        catalog_icons,
        on_disk=on_disk,
        license=license,
        attribution=attribution,
    )
    node = IconNode(ctx, llm=llm, catalog=catalog, generator=gen)
    return node, llm, gen


def test_icon_node_matched_only_skips_generation(tmp_path: Path) -> None:
    """When every slot matches within the set, no generation happens —
    no Recraft call and no prompt-authoring LLM call."""
    ctx = _run_ctx(tmp_path)
    matches = {
        "home_tab": "home",
        "search_action": "search",
        "celebration_badge": "badge",
    }
    node, llm, gen = _icon_node(
        ctx, matches=matches, catalog_icons=["home", "search", "badge"]
    )
    out = asyncio.run(node.run())

    assert set(out.icons) == set(matches)
    for sid, ic in out.icons.items():
        assert ic.icon_set == "set_a"
        # Matched icon_name is the set icon's short-name the LLM picked.
        assert ic.icon_name == matches[sid]
        assert ic.icon_key == sid
        assert ic.prompt is None
        assert Path(str(ic.path)).exists()
    assert gen.calls == []
    assert "IconPrompt" not in llm.calls


def test_icon_node_generation_path(tmp_path: Path) -> None:
    """An unmatched slot routes to generation: one batch prompt call, one
    Recraft call. The generated icon still belongs to the chosen set
    (icon_set == the set id), with an AI-authored icon_name + prompt."""
    ctx = _run_ctx(tmp_path)
    matches = {
        "home_tab": "home",
        "search_action": "search",
        "celebration_badge": None,
    }
    node, llm, gen = _icon_node(
        ctx, matches=matches, catalog_icons=["home", "search"]
    )
    out = asyncio.run(node.run())

    assert out.icons["home_tab"].icon_set == "set_a"
    # Matched icons carry no generation prompt.
    assert out.icons["home_tab"].prompt is None
    gen_out = out.icons["celebration_badge"]
    # Generated icon belongs to the chosen set, not a "generated" sentinel.
    assert gen_out.icon_set == "set_a"
    # AI-authored short icon name + the Recraft prompt that produced it.
    assert gen_out.icon_name == "celebration_badge_icon"
    assert gen_out.prompt == "a celebration_badge icon"
    assert Path(str(gen_out.path)).exists()
    assert len(gen.calls) == 1
    assert "IconPrompt" in llm.calls


def test_icon_node_records_attribution_for_cc_by_set(tmp_path: Path) -> None:
    """A chosen set whose licence requires credit (it declares an
    ``attribution`` notice) and from which an icon was actually copied
    surfaces that credit on ``IconSet.attribution``."""
    ctx = _run_ctx(tmp_path)
    notice = "Set A by Someone (CC BY 4.0) — https://example.test/by/4.0"
    node, _, _ = _icon_node(
        ctx,
        matches={
            "home_tab": "home",
            "search_action": "search",
            "celebration_badge": "badge",
        },
        catalog_icons=["home", "search", "badge"],
        license="CC-BY-4.0",
        attribution=notice,
    )
    out = asyncio.run(node.run())

    assert out.attribution is not None
    assert out.attribution.icon_set == "set_a"
    assert out.attribution.license == "CC-BY-4.0"
    assert out.attribution.notice == notice


def test_icon_node_no_attribution_for_permissive_set(tmp_path: Path) -> None:
    """A permissive set (no ``attribution`` notice) owes no credit, so
    ``IconSet.attribution`` stays ``None`` even with matched icons."""
    ctx = _run_ctx(tmp_path)
    node, _, _ = _icon_node(
        ctx,
        matches={
            "home_tab": "home",
            "search_action": "search",
            "celebration_badge": "badge",
        },
        catalog_icons=["home", "search", "badge"],
        license="MIT",
    )
    out = asyncio.run(node.run())

    assert out.attribution is None


def test_icon_node_no_attribution_when_nothing_matched(tmp_path: Path) -> None:
    """A CC-BY set chosen but matched by nothing (all slots generated)
    copies no licensed icon, so owes no credit."""
    ctx = _run_ctx(tmp_path)
    node, _, _ = _icon_node(
        ctx,
        matches={
            "home_tab": None,
            "search_action": None,
            "celebration_badge": None,
        },
        catalog_icons=["home"],
        license="CC-BY-4.0",
        attribution="Set A (CC BY 4.0)",
    )
    out = asyncio.run(node.run())

    assert out.attribution is None
    # the slots still resolved via generation
    assert out.icons["home_tab"].icon_set == "set_a"


def test_icon_node_fail_soft_drops_slot_with_missing_svg(
    tmp_path: Path,
) -> None:
    """A matched icon whose SVG is missing on disk is dropped (fail-soft),
    the rest still resolve."""
    ctx = _run_ctx(tmp_path)
    matches = {
        "home_tab": "home",
        "search_action": "search",
        "celebration_badge": "badge",
    }
    # 'home' is in the set's vocabulary (so matching validates) but has no
    # SVG on disk → its copy raises → the slot is dropped.
    node, _llm, _gen = _icon_node(
        ctx,
        matches=matches,
        catalog_icons=["home", "search", "badge"],
        on_disk=["search", "badge"],
    )
    out = asyncio.run(node.run())

    assert "home_tab" not in out.icons
    assert set(out.icons) == {"search_action", "celebration_badge"}


def test_build_icon_match_model_rejects_non_member() -> None:
    """A matched icon outside the chosen set's vocabulary fails validation
    (re-rides the structured-output retry loop); a null pick is allowed."""
    model = build_icon_match_model(["a"], icon_names=frozenset({"home"}))
    with pytest.raises(ValidationError):
        model(a=LLMIconResponse(icon="rocket", match_reason="x"))
    ok = model(a=LLMIconResponse(icon=None, match_reason="no match"))
    assert ok.a.icon is None


# --------------------------------------------------------------------------
# Classification node (src/modules/categories)
# --------------------------------------------------------------------------


class _FakeCompletion:
    """Minimal litellm completion stand-in: ``choices[0].message`` with the
    two access shapes ``LiteLLMClient`` uses (``["content"]`` + attribute)."""

    class _Message:
        def __init__(self, content: str) -> None:
            self.content = content

        def model_dump(self) -> dict:
            return {"role": "assistant", "content": self.content}

        def __getitem__(self, key: str) -> str:
            if key == "content":
                return self.content
            raise KeyError(key)

    class _Choice:
        def __init__(self, content: str) -> None:
            self.message = _FakeCompletion._Message(content)

    def __init__(self, content: str) -> None:
        self.choices = [self._Choice(content)]


class _CategoryStubLLM:
    """Stub LLMClient for the classification node: returns a canned pick and
    records the prompts it was shown."""

    cost = 0.0
    cost_by_model: dict[str, float] = {}

    def __init__(self, pick: str) -> None:
        self._pick = pick
        self.prompts: list[str] = []
        self.schemas: list[str] = []

    async def complete(self, *a: Any, **k: Any) -> Any:
        raise AssertionError("complete() not expected in these tests")

    async def complete_structured(
        self, messages: list[dict], *, schema: Any, **kw: Any
    ) -> Any:
        self.prompts.append(messages[0]["content"])
        self.schemas.append(getattr(schema, "__name__", ""))
        # Constructing the per-request model runs its vocabulary validator.
        return schema(category=self._pick, reason="fits")


def test_category_node_picks_from_the_declared_vocabulary(
    tmp_path: Path,
) -> None:
    """The node returns one of the app's own declared values, records the
    pseudo-slot as regenerated, and asks under the stable schema name."""
    ctx = _run_ctx(tmp_path)
    llm = _CategoryStubLLM("Modern")
    node = CategoryNode(ctx, llm=llm)

    out = asyncio.run(node.run())

    assert out.value == "Modern"
    assert out.value in ctx.app.categories
    assert out.reason
    assert node.regenerated == {CATEGORY_SLOT_ID}
    assert llm.schemas == ["CategorySelection"]


def test_category_node_seeded_does_not_call_the_llm(tmp_path: Path) -> None:
    """A run already classified seeds the node done: the saved value comes
    back verbatim and no call is made — reopening a classified run never
    re-spends on classification."""
    ctx = _run_ctx(tmp_path)
    llm = _CategoryStubLLM("Classic")
    node = CategoryNode(
        ctx, llm=llm, seed={CATEGORY_SLOT_ID: CategoryOutput(value="Modern")}
    )

    out = asyncio.run(node.run())

    assert out.value == "Modern"  # the seed, not the stub's pick
    assert node.dirty() == set()
    assert node.regenerated == set()
    assert llm.schemas == []


def test_category_prompt_is_data_driven(tmp_path: Path) -> None:
    """The prompt is built entirely from the two YAMLs — every declared
    bucket and the design brief appear, and the run's steering is folded in.
    Nothing app-specific is hardcoded in Python."""
    ctx = _run_ctx(tmp_path)
    ctx.overwrite_specs = OverwriteSpecs(specs="file it as the older style")
    llm = _CategoryStubLLM("Classic")
    asyncio.run(CategoryNode(ctx, llm=llm).run())

    prompt = llm.prompts[0]
    for bucket in ctx.app.categories:
        assert f"- {bucket}" in prompt
    assert ctx.cust.design_direction.name in prompt
    assert ctx.cust.design_direction.short_desc in prompt
    assert "file it as the older style" in prompt
    # The rule text lives in the .md, never in Python.
    assert CATEGORY_PROMPT_PATH.is_file()
    assert "$categories" in CATEGORY_PROMPT_PATH.read_text(encoding="utf-8")


def test_build_category_selection_model_rejects_non_member() -> None:
    """A pick outside the app's declared vocabulary fails validation (so it
    re-rides the structured-output retry loop instead of being written), and
    the error names the permitted values so the re-ask is actionable."""
    model = build_category_selection_model(frozenset({"Modern", "Classic"}))
    with pytest.raises(ValidationError) as exc:
        model(category="Brutalist", reason="x")
    assert "Modern" in str(exc.value) and "Classic" in str(exc.value)
    assert model(category="Modern", reason="x").category == "Modern"


def test_category_out_of_vocabulary_is_reasked_not_written(
    tmp_path: Path, monkeypatch
) -> None:
    """Through the REAL client retry loop: an out-of-vocabulary answer is fed
    back and re-asked, and only the in-vocabulary answer is returned. The
    vocabulary is never enforced by a static enum — it is the app's own."""
    import json

    import litellm

    from src.shared.services.llm_client import LiteLLMClient

    ctx = _run_ctx(tmp_path)
    replies = [
        json.dumps({"category": "Brutalist", "reason": "made up"}),
        json.dumps({"category": "Classic", "reason": "period detailing"}),
    ]
    seen: list[int] = []

    async def fake_acompletion(**kwargs):
        seen.append(len(kwargs["messages"]))
        return _FakeCompletion(replies[len(seen) - 1])

    monkeypatch.setattr(litellm, "acompletion", fake_acompletion)

    out = asyncio.run(
        CategorySelectionService(LiteLLMClient()).resolve(
            ctx, model="anthropic/claude-haiku-4-5"
        )
    )

    assert out.value == "Classic"
    assert len(seen) == 2  # first answer rejected, re-asked once
    assert seen[1] > seen[0]  # the correction turns were appended


def test_category_service_requires_a_vocabulary(tmp_path: Path) -> None:
    """Defense-in-depth: with no declared categories there is nothing to
    classify against, so the service refuses rather than inventing a value.
    (The registry never builds the node in that case.)"""
    ctx = _run_ctx(tmp_path)
    ctx.app = ctx.app.model_copy(update={"categories": []})
    with pytest.raises(ProviderError, match="no categories"):
        asyncio.run(
            CategorySelectionService(_CategoryStubLLM("Modern")).resolve(ctx)
        )


def test_recraft_call_cost_from_price_table() -> None:
    """Cost is the published per-image price for the model id; an unknown
    model id is $0 (never fabricated)."""
    cost = RecraftIconGenerator._call_cost
    # The icon path's vector model: $0.08.
    assert cost("recraftv4_1_utility_vector") == pytest.approx(0.08)
    assert cost("recraftv4_pro_vector") == pytest.approx(0.30)
    assert cost("recraftv3") == pytest.approx(0.04)
    assert cost("recraftv2_vector") == pytest.approx(0.044)
    # Every advertised model id is in the table.
    assert cost("recraftv4_1_utility_vector") == RECRAFT_PRICE_USD[
        "recraftv4_1_utility_vector"
    ]
    # Unknown model → $0, not a guess.
    assert cost("recraft_made_up_model") == 0.0
