"""Light, mocked tests for the two customization modules (no network)."""

from __future__ import annotations

import asyncio
from pathlib import Path
from typing import Any

import pytest
from pydantic import ValidationError

from schema import AppFormat, ColorOutput, Customization, ImageOutput
from src.core.run_context import RunContext
from src.core.util import load_yaml
from src.modules.colors.color_models import (
    ColorPalette,
    build_color_response_model,
)
from src.modules.colors.color_service import ColorGenService
from src.modules.images.image_models import BackgroundCheck, ImagePrompt
from src.modules.images.image_service import ImageGenService

APP_YAML = Path("apps/combatden/app.yaml")
CUST_YAML = Path("apps/combatden/customization.yaml")


def _run_ctx(tmp_path: Path) -> RunContext:
    app = AppFormat.model_validate(load_yaml(APP_YAML))
    cust = Customization.model_validate(load_yaml(CUST_YAML))
    return RunContext(app, cust, tmp_path)


def _full_palette(ctx: RunContext) -> ColorPalette:
    return ColorPalette(
        colors={
            slot.id: ColorOutput(
                hex="#AA1122", description=f"{slot.id} colour", vibe="bold"
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
    ) -> None:
        self._structured = structured
        self._structured_seq = structured_seq
        self._text = text
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
            result: Any = ImagePrompt(prompt=self._text, rationale="stub why")
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

    async def generate(self, prompt: str, dest: Path) -> Any:
        self.calls.append((prompt, dest))
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(b"raw-image-bytes")
        return str(dest.resolve())


class StubBgRemover:
    """Stub BackgroundRemover: writes a placeholder cutout at dst."""

    def __init__(self) -> None:
        self.calls: list[tuple[Path, Path]] = []

    async def remove(self, src: Path, dst: Path) -> None:
        self.calls.append((src, dst))
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_bytes(b"cutout-bytes")


# --- ColorGenService -------------------------------------------------------


def test_color_service_run_returns_full_palette(tmp_path: Path) -> None:
    ctx = _run_ctx(tmp_path)
    slot_ids = [slot.id for slot in ctx.app.colors]
    # The LLM answers with an instance of the per-request closed model.
    response_model = build_color_response_model(slot_ids)
    resolved = response_model(
        **{
            sid: ColorOutput(
                hex="#AA1122", description=f"{sid} colour", vibe="bold"
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
    model = build_color_response_model(["primary", "background"])
    only_one = (
        '{"primary": {"hex": "#AA1122", "description": "p", "vibe": "bold"}}'
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


def test_image_resolve_slot_fallback_when_validation_fails(
    tmp_path: Path,
) -> None:
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM(
        structured=BackgroundCheck(ok=False, reason="halo left"),
        text="prompt for the subject",
    )
    gen = StubImageGen()
    remover = StubBgRemover()
    mod = ImageGenService(ctx, llm=llm, image_gen=gen, bg_remover=remover)

    autocrop_calls: list[Any] = []
    import src.modules.images.image_service as image_service

    def _spy_autocrop(src: Path, dst: Path) -> None:
        autocrop_calls.append((src, dst))

    image_service.autocrop_symmetric = _spy_autocrop

    out = asyncio.run(mod.run(slot, palette))

    expected_path = str(ctx.image_path(slot.id))
    assert isinstance(out, ImageOutput)
    assert str(out.path) == expected_path
    assert out.prompt == "prompt for the subject"
    # Fallback: raw copied to final, autocrop NOT called.
    assert autocrop_calls == []
    assert Path(expected_path).read_bytes() == b"raw-image-bytes"
    # Remover retried up to the cap.
    from src.core.config import settings

    assert len(remover.calls) == settings.bg_max_attempts


def test_image_resolve_slot_happy_path_autocrops(tmp_path: Path) -> None:
    ctx = _run_ctx(tmp_path)
    palette = _full_palette(ctx)
    slot = ctx.app.images[0]

    llm = StubLLM(structured=BackgroundCheck(ok=True, reason="clean"))
    gen = StubImageGen()
    remover = StubBgRemover()
    mod = ImageGenService(ctx, llm=llm, image_gen=gen, bg_remover=remover)

    autocrop_calls: list[tuple[Path, Path]] = []
    import src.modules.images.image_service as image_service

    def _spy_autocrop(src: Path, dst: Path) -> None:
        autocrop_calls.append((src, dst))
        Path(dst).write_bytes(b"cropped")

    image_service.autocrop_symmetric = _spy_autocrop

    out = asyncio.run(mod.run(slot, palette))

    expected_path = str(ctx.image_path(slot.id))
    assert str(out.path) == expected_path
    # Happy path: autocrop invoked exactly once, dst is the final path.
    assert len(autocrop_calls) == 1
    assert str(autocrop_calls[0][1]) == expected_path
    assert Path(expected_path).read_bytes() == b"cropped"
    assert len(remover.calls) == 1
