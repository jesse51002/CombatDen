"""ImageNode — one image graph node: resolve a single image slot.

One instance per image slot (the registry builds the list; the executor
schedules them). Atomic per image: write the prompt, classify its
complexity (which picks the generator's quality tier), generate, then
hand off to the ``BackgroundService`` for removal/crop. ``color`` is an
automatic dependency; declared ``depends_on`` images arrive as resolved
inputs and are always used as *reference* (their look is folded into the
prompt text for visual continuity — never fed in as an input image).
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template
from typing import Any

from schema import ColorMode, Complexity, ImageOutput, ImageSlot
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.images.background_service import BackgroundService
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_edit_service import ImageEditService
from src.modules.images.image_models import ImagePrompt
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

IMAGE_PROMPT_PATH = Path(__file__).parent / "prompts" / "image_prompt_rule.md"
# Injected into the main prompt ONLY when the slot has image
# dependencies: the visual-continuity guidance plus the per-dependency
# listing. Kept separate so the common no-dependency prompt carries no
# dependency wording at all. Dependencies are always reference.
RELATED_ASSETS_PATH = Path(__file__).parent / "prompts" / "related_assets.md"
RAW_SUFFIX = ".raw.png"
# A retried generation reuses the canonical ``{slot}.raw.png`` dest; before
# the next attempt overwrites a file a prior attempt already wrote, that
# file is moved aside under this name so the full attempt lineage survives
# on disk for inspection. ``{n}`` is the 1-based number of the preserved
# attempt. The happy path (no retry) never produces one of these.
RAW_ATTEMPT_TMPL = "{stem}.attempt{n}.png"
# The asset composites onto the app's own base surface, so the generated
# background is fixed to that surface by theme: a matching flat field makes
# the cutout trivial. Named literally — image models render these reliably.
THEME_BG_DARK = "pure black (the app is in dark mode)"
THEME_BG_LIGHT = "pure white (the app is in light mode)"

# Per-call constants, not config — this flow is now too specific for
# global config. Override in dev (bake-off scripts under `scripts/`);
# production uses these. ``IMAGE_GEN_MODEL`` is provider-prefixed and the
# generic litellm image generator routes on it (swap providers here).
IMAGE_PROMPT_MODEL = "anthropic/claude-opus-4-7"
IMAGE_GEN_MODEL = "openai/gpt-image-2"
# Bounded re-calls: image-provider moderation/infra is non-deterministic,
# so a benign prompt can blip on one call and pass the next. There is no
# usable fallback for a missing image, so exhaustion fails the run.
IMAGE_GEN_MAX_ATTEMPTS = 3
# Complexity tier → generator quality. ``high`` is reserved/unused for now
# (overkill); flip it to "high" here to enable it — no schema change.
QUALITY_BY_COMPLEXITY: dict[Complexity, str] = {
    Complexity.LOW: "low",
    Complexity.MEDIUM: "medium",
    Complexity.HIGH: "medium",
}


class ImageNode(Node):
    """One image node, atomic per image: ``run() -> ImageOutput``.

    ``slot`` and ``deps`` are construction state; ``color`` (the palette)
    and any ``depends_on`` images arrive via ``inputs`` set by the
    executor just before ``run()``.
    """

    def __init__(
        self,
        run_ctx: RunContext,
        *,
        slot: ImageSlot,
        deps: frozenset[str],
        llm: LLMClient,
        image_gen: ImageGenerator,
        classifier: ComplexityClassifier,
        background: BackgroundService,
        seed: dict[str, ImageOutput] | None = None,
        overwrite_specs: str = "",
    ) -> None:
        super().__init__(
            run_ctx,
            key=slot.id,
            deps=deps,
            declared_slots={slot.id},
            seed=seed,
            overwrite_specs=overwrite_specs,
        )
        self._slot = slot
        self._llm = llm
        self._image_gen = image_gen
        self._classifier = classifier
        self._background = background
        self._edit = ImageEditService(llm)

    async def run(self, *, prompt_model: str = IMAGE_PROMPT_MODEL) -> ImageOutput:
        """Resolve this slot end to end: deps → prompt → classify →
        generate → cutout → crop.

        ``prompt_model`` drives the prompt-generation call (override in dev
        to compare models). Complexity classification picks the generator's
        quality tier. Declared image dependencies are folded into the
        prompt as style reference only; the background pass — delegated to
        ``BackgroundService`` — runs on the generated image.

        A per-slot node: a seeded, un-overridden image (nothing dirty) is
        returned verbatim with no generation — so reopening a run to change
        one thing never re-bills every untouched image."""
        dirty = self.dirty()
        self.regenerated = dirty
        if not dirty:
            return self.seed[self._slot.id]  # type: ignore[return-value]
        palette = self.inputs[DependencyKind.COLOR.value]
        # Image-to-image: when the steering carries an ``image_to_image`` and
        # a current image exists, edit it (change only what was asked) rather
        # than generate a fresh scene.
        if self.overwrite_specs.image_to_image is not None:
            source = Path(str(self._run_ctx.image_path(self._slot.id)))
            if source.is_file():
                return await self._edit_current(palette, source)
        image_deps: dict[str, ImageOutput] = {
            dep_id: self.inputs[dep_id]  # type: ignore[misc]
            for dep_id in self._slot.depends_on
        }
        prompt = await self._build_prompt(
            palette, image_deps, model=prompt_model
        )
        complexity = await self._classifier.classify(prompt)
        quality = QUALITY_BY_COMPLEXITY[complexity]
        raw = await self._generate(prompt, quality)
        final = Path(str(self._run_ctx.image_path(self._slot.id)))

        await self._background.run(raw, final)
        return ImageOutput(
            path=self._run_ctx.image_path(self._slot.id),
            prompt=prompt,
            complexity=complexity,
            overwrite_specs=self.overwrite_specs,
        )

    async def _edit_current(
        self, palette: Any, source: Path
    ) -> ImageOutput:
        """Image-to-image: author the edit instruction (the change only) and
        edit ``source`` in place, then run the same background pass. The
        prompt recorded is the edit instruction; complexity is ``None`` (no
        classify on an edit)."""
        instruction = await self._edit.author(
            self._run_ctx,
            slot=self._slot,
            palette=palette,
            change=self.overwrite_specs.specs,
        )
        raw = self._run_ctx.image_dir / f"{self._slot.id}.edit{RAW_SUFFIX}"
        await self._image_gen.edit(
            instruction, source, raw, model=IMAGE_GEN_MODEL
        )
        final = Path(str(self._run_ctx.image_path(self._slot.id)))
        await self._background.run(raw, final)
        return ImageOutput(
            path=self._run_ctx.image_path(self._slot.id),
            prompt=instruction,
            complexity=None,
            overwrite_specs=self.overwrite_specs,
        )

    async def _build_prompt(
        self,
        palette: Any,
        image_deps: dict[str, ImageOutput],
        *,
        model: str = IMAGE_PROMPT_MODEL,
    ) -> str:
        """Brief + slot + palette (+ related-asset block) → ``prompt``.

        The related-assets block — visual-continuity guidance plus the
        per-dependency listing — is a separate prompt fragment injected
        ONLY when the slot has image dependencies; otherwise nothing about
        dependencies reaches the model. Dependencies are always used as
        *reference*: their look is folded into the prompt text, never fed
        in as an input image."""
        template = IMAGE_PROMPT_PATH.read_text(encoding="utf-8")
        design = self._run_ctx.cust.design_direction
        dark_mode = self._run_ctx.cust.colors_direction.mode is ColorMode.DARK
        palette_summary = "\n".join(
            # OklchColor.__str__ gives the canonical CSS string form
            # (`oklch(70.5% 0.19 41)`) — easier for the image-gen model to
            # reason about than the wire JSON `{l, c, h}`.
            f"  {slot_id}: {color.color.oklch!s} — "
            f"{color.display_name}: {color.description}"
            for slot_id, color in palette.colors.items()
        )
        if image_deps:
            listing = "\n".join(
                f"  {dep_id}: {out.prompt}"
                for dep_id, out in image_deps.items()
            )
            fragment = RELATED_ASSETS_PATH.read_text(encoding="utf-8")
            related_assets = Template(fragment).safe_substitute(
                dependencies=listing
            )
        else:
            related_assets = ""
        prompt = Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            palette=palette_summary,
            theme_background=(THEME_BG_DARK if dark_mode else THEME_BG_LIGHT),
            subject=self._slot.description,
            related_assets=related_assets,
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": prompt}],
            schema=ImagePrompt,
            model=model,
        )
        return result.prompt

    async def _generate(self, prompt: str, quality: str) -> Path:
        """Generate the raw image (subject on a plain solid background).

        Text-to-image only — declared dependencies are reference (folded
        into ``prompt``), never fed to the generator.

        The image provider's moderation/infra is non-deterministic — a
        benign prompt can hit a false-positive block, a transient failure,
        or a timeout on one call and succeed on the next — so generation is
        retried a bounded number of times. Unlike background removal there
        is no usable fallback for a missing image, so exhaustion re-raises
        the last provider error and fails the run.
        """
        dest = self._run_ctx.image_dir / f"{self._slot.id}{RAW_SUFFIX}"
        last_error: ProviderError | None = None
        for attempt in range(IMAGE_GEN_MAX_ATTEMPTS):
            # Never clobber a file an earlier attempt actually wrote: move
            # it aside under its attempt number before this one overwrites
            # the canonical dest. (A hard-failed attempt raises before
            # writing, so usually there is nothing here to preserve.)
            if attempt and dest.exists():
                dest.rename(
                    dest.with_name(
                        RAW_ATTEMPT_TMPL.format(stem=dest.stem, n=attempt)
                    )
                )
            try:
                await self._image_gen.generate(
                    prompt, dest, model=IMAGE_GEN_MODEL, quality=quality
                )
                return dest
            except ProviderError as exc:
                last_error = exc
                logger.warning(
                    "image generation failed on attempt %d/%d for %s: %s",
                    attempt + 1,
                    IMAGE_GEN_MAX_ATTEMPTS,
                    self._slot.id,
                    exc,
                )
        raise last_error or ProviderError(
            f"image generation produced nothing for {self._slot.id}"
        )
