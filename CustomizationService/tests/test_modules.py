"""Light, mocked tests for the two customization modules (no network)."""

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
    ImageOutput,
)
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.core.util import load_yaml
from src.modules.colors.color_models import (
    ColorPalette,
    build_color_response_model,
)
from src.modules.colors.color_service import ColorGenService
from src.modules.images.background_service import (
    BG_MAX_ATTEMPTS,
    BackgroundService,
)
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_models import (
    BackgroundCheck,
    ImageComplexity,
    ImagePrompt,
)
from src.modules.images.image_service import ImageGenService

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
    """Stub ImageGenerator: writes a tiny placeholder file at dest."""

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
    """Stub BackgroundRemover: writes a real (mostly transparent) PNG so
    the deterministic alpha gate in ``validate_cutout`` can read it."""

    def __init__(self) -> None:
        self.calls: list[tuple[Path, Path]] = []

    async def remove(self, src: Path, dst: Path) -> None:
        self.calls.append((src, dst))
        dst.parent.mkdir(parents=True, exist_ok=True)
        Image.new("RGBA", (16, 16), (0, 0, 0, 0)).save(dst)


def _image_service(
    ctx: RunContext,
    llm: Any,
    *,
    image_gen: Any = None,
    remover: Any = None,
) -> ImageGenService:
    """Build an ImageGenService with real classifier + background sub-
    services wired to the same stub llm (mirrors the registry)."""
    return ImageGenService(
        ctx,
        llm=llm,
        image_gen=image_gen if image_gen is not None else StubImageGen(),
        classifier=ComplexityClassifier(ctx, llm=llm),
        background=BackgroundService(
            ctx,
            llm=llm,
            bg_remover=remover if remover is not None else StubBgRemover(),
        ),
    )


# --- ColorGenService -------------------------------------------------------


def test_color_service_run_returns_full_palette(tmp_path: Path) -> None:
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
    mod = ColorGenService(ctx, llm=llm)

    result = asyncio.run(mod.run())

    # run() flattens the closed model back into a ColorPalette map.
    assert isinstance(result, ColorPalette)
    assert set(result.colors) == set(slot_ids)
    # Exactly one structured call.
    assert len(llm.structured_calls) == 1


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
    mod = ColorGenService(ctx, llm=StubLLM())

    from src.modules.colors.color_service import COLOR_PROMPT_PATH

    prompt = mod._build_prompt()
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


# --- ImageGenService -------------------------------------------------------


@pytest.mark.skip(
    reason="background validation temporarily disabled in "
    "BackgroundService._remove_background; re-enable this test when the "
    "validate_cutout block is uncommented"
)
def test_image_resolve_slot_keeps_rejected_cutout(tmp_path: Path) -> None:
    """A produced-but-rejected cutout is kept and autocropped — a bad
    cutout beats the un-removed image."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM(
        structured=BackgroundCheck(ok=False, reason="halo left"),
        text="prompt for the subject",
    )
    gen = StubImageGen()
    remover = StubBgRemover()
    mod = _image_service(ctx, llm, image_gen=gen, remover=remover)

    autocrop_calls: list[tuple[Path, Path]] = []
    import src.modules.images.background_service as background_service

    def _spy_autocrop(src: Path, dst: Path) -> None:
        autocrop_calls.append((src, dst))
        Path(dst).write_bytes(b"cropped")

    background_service.autocrop = _spy_autocrop

    out = asyncio.run(mod.run(slot, palette))

    expected_path = str(ctx.image_path(slot.id))
    assert isinstance(out, ImageOutput)
    assert str(out.path) == expected_path
    assert out.prompt == "prompt for the subject"
    assert out.complexity == Complexity.LOW
    # Rejected cutout kept: autocrop called once, on the *cutout* (not raw).
    assert len(autocrop_calls) == 1
    assert str(autocrop_calls[0][0]).endswith(".raw.cutout.png")
    assert not str(autocrop_calls[0][0]).endswith(".raw.png")
    assert str(autocrop_calls[0][1]) == expected_path
    assert Path(expected_path).read_bytes() == b"cropped"
    # Every verdict failed, so the remover retried up to the cap.
    assert len(remover.calls) == BG_MAX_ATTEMPTS


def test_image_resolve_slot_falls_back_to_raw_when_no_cutout(
    tmp_path: Path,
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

    llm = StubLLM(
        structured=BackgroundCheck(ok=True, reason="unused"),
        text="prompt for the subject",
    )
    gen = StubImageGen()
    remover = FailingBgRemover()
    mod = _image_service(ctx, llm, image_gen=gen, remover=remover)

    autocrop_calls: list[Any] = []
    import src.modules.images.background_service as background_service

    def _spy_autocrop(src: Path, dst: Path) -> None:
        autocrop_calls.append((src, dst))

    background_service.autocrop = _spy_autocrop

    out = asyncio.run(mod.run(slot, palette))

    expected_path = str(ctx.image_path(slot.id))
    assert str(out.path) == expected_path
    # No cutout ever produced: raw copied to final, autocrop NOT called.
    assert autocrop_calls == []
    assert Path(expected_path).read_bytes() == b"raw-image-bytes"
    # Remover retried up to the cap (every attempt raised).
    assert len(remover.calls) == BG_MAX_ATTEMPTS


def test_image_resolve_slot_happy_path_autocrops(tmp_path: Path) -> None:
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM(structured=BackgroundCheck(ok=True, reason="clean"))
    gen = StubImageGen()
    remover = StubBgRemover()
    mod = _image_service(ctx, llm, image_gen=gen, remover=remover)

    autocrop_calls: list[tuple[Path, Path]] = []
    import src.modules.images.background_service as background_service

    def _spy_autocrop(src: Path, dst: Path) -> None:
        autocrop_calls.append((src, dst))
        Path(dst).write_bytes(b"cropped")

    background_service.autocrop = _spy_autocrop

    out = asyncio.run(mod.run(slot, palette))

    expected_path = str(ctx.image_path(slot.id))
    assert str(out.path) == expected_path
    # Happy path: autocrop invoked exactly once, dst is the final path.
    assert len(autocrop_calls) == 1
    assert str(autocrop_calls[0][1]) == expected_path
    assert Path(expected_path).read_bytes() == b"cropped"
    assert len(remover.calls) == 1


def test_image_prompt_is_app_agnostic_and_theme_fixed(
    tmp_path: Path,
) -> None:
    """The rule file hardcodes no house style, and the built prompt names
    the flat background by the app's light/dark theme."""
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    from src.modules.images.image_service import (
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
        mod = _image_service(ctx, llm)
        asyncio.run(mod._build_prompt(slot, palette))
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


# --- validate_cutout: deterministic alpha gate before the model ----------


def test_validate_cutout_short_circuits_on_opaque_image(
    tmp_path: Path,
) -> None:
    """Too little transparency in the cutout → deterministic reject, no
    model call: a vision model can't see alpha, so pixels decide 'backdrop
    removed' before the original is ever shown."""
    original = tmp_path / "original.png"
    Image.new("RGBA", (32, 32), (200, 30, 30, 255)).save(original)
    cutout = tmp_path / "opaque.png"
    Image.new("RGBA", (32, 32), (200, 200, 200, 255)).save(cutout)

    class _NoLLM:
        async def complete_structured(self, *a: Any, **k: Any) -> Any:
            raise AssertionError("model must not be called on opaque cutout")

    verdict = asyncio.run(
        BackgroundService(llm=_NoLLM()).validate_cutout(original, cutout)
    )

    assert verdict.ok is False
    assert "not removed" in verdict.reason


def test_validate_cutout_sends_before_and_after_when_transparent_enough(
    tmp_path: Path,
) -> None:
    original = tmp_path / "original.png"
    Image.new("RGBA", (32, 32), (200, 30, 30, 255)).save(original)
    cutout = tmp_path / "clear.png"
    Image.new("RGBA", (32, 32), (0, 0, 0, 0)).save(cutout)
    llm = StubLLM(structured=BackgroundCheck(ok=True, reason="subject ok"))

    verdict = asyncio.run(
        BackgroundService(llm=llm).validate_cutout(original, cutout)
    )

    assert verdict.ok is True
    assert verdict.reason == "subject ok"
    assert len(llm.structured_calls) == 1
    # One instruction text + the two images (BEFORE then AFTER, by order).
    content = llm.structured_calls[0]["messages"][0]["content"]
    texts = [c["text"] for c in content if c["type"] == "text"]
    images = [c for c in content if c["type"] == "image_url"]
    assert len(images) == 2
    assert len(texts) == 1
    instruction = texts[0]
    # The $alpha placeholder is substituted with the measured value (the
    # cutout here is fully transparent → 100%).
    assert "$alpha" not in instruction
    assert "100%" in instruction
