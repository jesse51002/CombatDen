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
    ColorOutput,
    ColorRole,
    Complexity,
    Customization,
    DependencyUsage,
    ImageOutput,
)
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.core.util import load_yaml
from src.modules.base import DependencyKind
from src.modules.colors.color_models import (
    ColorPalette,
    build_color_response_model,
)
from src.modules.colors.color_node import ColorNode
from src.modules.images.background_service import (
    BG_MAX_ATTEMPTS,
    BackgroundService,
)
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_models import (
    DependencyUsageEntry,
    ImageComplexity,
    ImagePrompt,
    StyleCheck,
)
from src.modules.images.image_node import ImageNode
from src.modules.images.style_service import StyleAdherenceService

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
    return ColorPalette(
        colors={
            slot.id: ColorOutput(
                oklch="oklch(55% 0.12 250)",
                display_name=f"{slot.id} tone",
                description=f"{slot.id} colour",
            )
            for slot in ctx.app.colors
        }
    )


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
        style: StyleCheck | None = None,
        dep_usage: list[DependencyUsageEntry] | None = None,
    ) -> None:
        self._structured = structured
        self._structured_seq = structured_seq
        self._text = text
        self._complexity = complexity
        self._dep_usage = dep_usage
        # Default: adherent, so the style check is a no-op unless a test
        # opts into an off-style verdict.
        self._style = style or StyleCheck(
            adherent=True, reason="", edit_instruction=""
        )
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
            result: Any = ImagePrompt(
                prompt=self._text,
                dependency_usage=self._dep_usage or [],
            )
        elif schema is ImageComplexity:
            result = ImageComplexity(complexity=self._complexity)
        elif schema is StyleCheck:
            result = self._style
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
    """Stub ImageGenerator: writes a placeholder file for generate + edit
    and records both call streams."""

    def __init__(self) -> None:
        self.calls: list[tuple[str, Path]] = []
        self.edits: list[tuple[Path, str, Path]] = []
        self.composes: list[tuple[str, list[Path], Path]] = []

    async def generate(
        self, prompt: str, dest: Path, *, model: str, quality: str
    ) -> Any:
        self.calls.append((prompt, dest))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"raw-image-bytes")
        return str(dest.resolve())

    async def edit(
        self, src: Path, instruction: str, dest: Path, *, model: str
    ) -> Any:
        self.edits.append((src, instruction, dest))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"edited-image-bytes")
        return str(dest.resolve())

    async def compose(
        self,
        prompt: str,
        srcs: list[Path],
        dest: Path,
        *,
        model: str,
        quality: str,
    ) -> Any:
        self.composes.append((prompt, list(srcs), dest))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"composed-image-bytes")
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
    """Build one per-slot ImageNode with real classifier + style +
    background sub-services wired to the same stub llm (mirrors the
    registry). The image-gen stub serves generate, edit and compose (one
    contract). The reference/direct verdict is no longer a sub-service —
    the stub llm answers it inline on the ImagePrompt call. ``deps`` is
    the slot's dependency-key set (default: colour only); pass the
    declared ``depends_on`` ids too for a slot that builds on others."""
    return ImageNode(
        ctx,
        slot=slot,
        deps=deps,
        llm=llm,
        image_gen=image_gen if image_gen is not None else StubImageGen(),
        classifier=ComplexityClassifier(llm=llm),
        style=StyleAdherenceService(llm=llm),
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
    dark_mode = ctx.cust.colors_direction.dark_mode
    # The LLM answers with an instance of the per-request closed model;
    # constructing it runs the deterministic contract after-validator, so
    # the stubbed palette must satisfy it.
    response_model = build_color_response_model(
        slot_ids, roles=roles, dark_mode=dark_mode
    )
    resolved = response_model(
        **{
            sid: ColorOutput(
                oklch=_contract_oklch(roles[sid], dark_mode),
                display_name=f"{sid} tone",
                description=f"{sid} colour",
            )
            for sid in slot_ids
        }
    )
    llm = StubLLM(structured=resolved)
    node = ColorNode(ctx, llm=llm)

    result = asyncio.run(node.run())

    # run() flattens the closed model back into a ColorPalette map.
    assert isinstance(result, ColorPalette)
    assert set(result.colors) == set(slot_ids)
    # Exactly one structured call.
    assert len(llm.structured_calls) == 1
    # The colour node is the DAG root: keyed "color", no dependencies.
    assert node.key == _COLOR
    assert node.deps == frozenset()


def test_color_response_model_rejects_missing_slot() -> None:
    """Completeness is structural: the per-slot model is required-only, so a
    payload missing a slot fails validation (re-asked by the client loop)."""
    model = build_color_response_model(
        ["primary", "background"],
        roles={"primary": None, "background": ColorRole.BACKGROUND},
        dark_mode=True,
    )
    only_one = (
        '{"primary": {"oklch": "oklch(55% 0.15 25)", '
        '"display_name": "P", "description": "p"}}'
    )

    with pytest.raises(ValidationError) as exc:
        model.model_validate_json(only_one)

    # The omitted slot is the reported missing field.
    assert "background" in str(exc.value)


def test_color_prompt_is_data_driven(tmp_path: Path) -> None:
    ctx = _run_ctx(tmp_path)
    node = ColorNode(ctx, llm=StubLLM())

    from src.modules.colors.color_node import COLOR_PROMPT_PATH

    prompt = node._build_prompt()
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
        ctx.cust.colors_direction.dark_mode = dark_mode
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


def test_image_adherent_skips_edit(tmp_path: Path) -> None:
    """Adherent verdict: no edit; output records adherent, no edit fields."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM(
        style=StyleCheck(adherent=True, reason="", edit_instruction="")
    )
    gen = StubImageGen()
    remover = StubBgRemover()
    node = _image_node(ctx, llm, slot, image_gen=gen, remover=remover)

    out = _resolve(node, palette)

    # No corrective edit; the raw image is what bg-removal received.
    assert gen.edits == []
    assert remover.calls[0][0].name == f"{slot.id}.raw.png"
    assert out.adherent is True
    assert out.edited_prompt is None
    assert out.edited_reason is None


def test_image_off_style_edits_once_and_records(tmp_path: Path) -> None:
    """Off-style verdict: exactly one edit, the edited image flows to
    bg-removal, and the verdict is recorded on the output."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM(
        style=StyleCheck(
            adherent=False,
            reason="too generic for the prompt's stated style",
            edit_instruction="make the finish forged matte gunmetal",
        )
    )
    gen = StubImageGen()
    remover = StubBgRemover()
    node = _image_node(ctx, llm, slot, image_gen=gen, remover=remover)

    out = _resolve(node, palette)

    # Exactly one edit, fed the instruction verbatim, on the raw image.
    assert len(gen.edits) == 1
    edit_src, instruction, edit_dest = gen.edits[0]
    assert edit_src.name == f"{slot.id}.raw.png"
    assert instruction == "make the finish forged matte gunmetal"
    # Background removal ran on the EDITED image, not the raw one.
    assert remover.calls[0][0] == edit_dest
    assert edit_dest.name == f"{slot.id}.raw.edited.png"
    # Provenance recorded on the output.
    assert out.adherent is False
    assert out.edited_prompt == "make the finish forged matte gunmetal"
    assert out.edited_reason == "too generic for the prompt's stated style"


# --- ImageNode with image dependencies (depends_on) ------------------------

_DEP_CUST = {
    "design_direction": {
        "name": "Demo",
        "short_desc": "short",
        "long_desc": "long",
    },
    "colors_direction": {"description": "calm", "dark_mode": True},
}
_DEP_COLORS = [
    {"id": "primary", "description": "primary"},
    {"id": "background", "description": "bg", "role": "background"},
    {"id": "text", "description": "text", "role": "text"},
    {"id": "accent", "description": "accent"},
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


def test_image_dependency_reference_folds_into_prompt(
    tmp_path: Path,
) -> None:
    """A REFERENCE verdict: the dependency is listed in the injected
    block, generation stays text-to-image, and the verdict is recorded."""
    ctx = _dep_ctx(tmp_path)
    palette = _full_palette(ctx)
    derived = ctx.app.images[1]
    hero = ImageOutput(path=ctx.image_path("hero"), prompt="hero prompt")

    llm = StubLLM(
        dep_usage=[
            DependencyUsageEntry(
                dependency="hero", usage=DependencyUsage.REFERENCE
            )
        ]
    )
    gen = StubImageGen()
    node = _image_node(
        ctx, llm, derived, image_gen=gen, deps=frozenset({_COLOR, "hero"})
    )

    out = _run_derived(node, palette, hero)

    sent = llm.structured_calls[0]["messages"][0]["content"]
    assert "Related assets (visual continuity)" in sent
    assert "hero: hero prompt" in sent
    # Text-to-image: no DIRECT dependency to feed in.
    assert len(gen.calls) == 1
    assert gen.composes == []
    assert out.dependency_usage == {"hero": DependencyUsage.REFERENCE}


def test_image_dependency_direct_feeds_image_into_compose(
    tmp_path: Path,
) -> None:
    """A DIRECT verdict: the dependency image itself is fed to ``compose``
    (image-conditioned generation), not text-to-image, and recorded."""
    ctx = _dep_ctx(tmp_path)
    palette = _full_palette(ctx)
    derived = ctx.app.images[1]
    hero_path = Path(str(ctx.image_path("hero")))
    hero_path.parent.mkdir(parents=True, exist_ok=True)
    Image.new("RGB", (32, 32), (10, 10, 10)).save(hero_path)
    hero = ImageOutput(path=ctx.image_path("hero"), prompt="hero prompt")

    llm = StubLLM(
        dep_usage=[
            DependencyUsageEntry(
                dependency="hero", usage=DependencyUsage.DIRECT
            )
        ]
    )
    gen = StubImageGen()
    node = _image_node(
        ctx, llm, derived, image_gen=gen, deps=frozenset({_COLOR, "hero"})
    )

    out = _run_derived(node, palette, hero)

    # Image-conditioned: compose got the hero image, generate untouched.
    assert gen.calls == []
    assert len(gen.composes) == 1
    _, srcs, _ = gen.composes[0]
    assert srcs == [hero_path]
    assert out.dependency_usage == {"hero": DependencyUsage.DIRECT}


def test_image_no_dependency_block_absent_and_usage_none(
    tmp_path: Path,
) -> None:
    """A slot with no image dependencies: nothing about dependencies
    reaches the model and ``dependency_usage`` is ``None``."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM()
    node = _image_node(ctx, llm, slot)
    out = _resolve(node, palette)

    sent = llm.structured_calls[0]["messages"][0]["content"]
    assert "Related assets (visual continuity)" not in sent
    assert "$dependency_block" not in sent
    assert out.dependency_usage is None


def test_image_dependency_usage_normalised(tmp_path: Path) -> None:
    """An undeclared id is dropped and a declared id the model skipped
    defaults to REFERENCE — so a hallucinated DIRECT never feeds compose."""
    ctx = _dep_ctx(tmp_path)
    palette = _full_palette(ctx)
    derived = ctx.app.images[1]
    hero = ImageOutput(path=ctx.image_path("hero"), prompt="hero prompt")

    llm = StubLLM(
        dep_usage=[
            DependencyUsageEntry(
                dependency="ghost", usage=DependencyUsage.DIRECT
            )
        ]
    )
    gen = StubImageGen()
    node = _image_node(
        ctx, llm, derived, image_gen=gen, deps=frozenset({_COLOR, "hero"})
    )

    out = _run_derived(node, palette, hero)

    assert out.dependency_usage == {"hero": DependencyUsage.REFERENCE}
    assert gen.composes == []
    assert len(gen.calls) == 1
