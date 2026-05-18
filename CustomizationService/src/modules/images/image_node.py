"""ImageNode — one image graph node: resolve a single image slot.

One instance per image slot (the registry builds the list; the executor
schedules them). Atomic per image: write the prompt, classify its
complexity (which picks the generator's quality tier), generate, style
check, one-time corrective edit on a miss, then hand off to the
``BackgroundService`` for removal/crop. ``color`` is an automatic
dependency; declared ``depends_on`` images arrive as resolved inputs.
"""

from __future__ import annotations

import logging
from pathlib import Path
from string import Template
from typing import Any

from schema import Complexity, DependencyUsage, ImageOutput, ImageSlot
from src.core.errors import ProviderError
from src.core.run_context import RunContext
from src.modules.base import DependencyKind, Node
from src.modules.colors.color_models import ColorPalette
from src.modules.images.background_service import BackgroundService
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_models import DependencyUsageEntry, ImagePrompt
from src.modules.images.style_service import StyleAdherenceService
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

IMAGE_PROMPT_PATH = Path(__file__).parent / "prompts" / "image_prompt_rule.md"
# Injected into the main prompt ONLY when the slot has image
# dependencies: the visual-continuity + reference/direct decision rules
# and the per-dependency listing. Kept separate so the common
# no-dependency prompt carries no dependency wording at all.
DEP_BLOCK_PATH = Path(__file__).parent / "prompts" / "dependency_usage.md"
RAW_SUFFIX = ".raw.png"
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
# Regular nano-banana, via litellm's image-edit path. Per-call constant
# (one-line swap), same as the other model ids here. Used once, only when
# the style check fails — never looped.
STYLE_EDIT_MODEL = "gemini/gemini-2.5-flash-image-preview"
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
        style: StyleAdherenceService,
        background: BackgroundService,
    ) -> None:
        super().__init__(run_ctx, key=slot.id, deps=deps)
        self._slot = slot
        self._llm = llm
        self._image_gen = image_gen
        self._classifier = classifier
        self._style = style
        self._background = background

    async def run(self, *, prompt_model: str = IMAGE_PROMPT_MODEL) -> ImageOutput:
        """Resolve this slot end to end: deps → prompt → classify →
        generate → style check → (one-time edit) → cutout → crop.

        ``prompt_model`` drives the prompt-generation call (override in dev
        to compare models). Complexity classification picks the generator's
        quality tier. The style check judges whether the raw image realises
        the prompt; on a miss exactly one corrective edit is applied (no
        loop, no re-check) before the background pass — delegated to
        ``BackgroundService`` — runs on the resulting image."""
        palette = self.inputs[DependencyKind.COLOR.value]
        image_deps: dict[str, ImageOutput] = {
            dep_id: self.inputs[dep_id]  # type: ignore[misc]
            for dep_id in self._slot.depends_on
        }
        prompt, usage = await self._build_prompt(
            palette, image_deps, model=prompt_model
        )
        direct_deps: dict[str, ImageOutput] = {
            dep_id: image_deps[dep_id]
            for dep_id, used_as in (usage or {}).items()
            if used_as is DependencyUsage.DIRECT
        }
        complexity = await self._classifier.classify(prompt)
        quality = QUALITY_BY_COMPLEXITY[complexity]
        raw = await self._generate(prompt, quality, direct_deps)
        final = Path(str(self._run_ctx.image_path(self._slot.id)))

        verdict = await self._style.check(raw, prompt)
        edited_prompt: str | None = None
        edited_reason: str | None = None
        if not verdict.adherent:
            # One corrective pass only: if a single targeted edit toward
            # the prompt's style does not land, more won't — so we ship
            # the edited image as-is, no re-check.
            edited = raw.with_name(f"{raw.stem}.edited.png")
            await self._image_gen.edit(
                raw,
                verdict.edit_instruction,
                edited,
                model=STYLE_EDIT_MODEL,
            )
            raw = edited
            edited_prompt = verdict.edit_instruction
            edited_reason = verdict.reason

        await self._background.run(raw, final)
        return ImageOutput(
            path=self._run_ctx.image_path(self._slot.id),
            prompt=prompt,
            complexity=complexity,
            adherent=verdict.adherent,
            edited_prompt=edited_prompt,
            edited_reason=edited_reason,
            dependency_usage=usage,
        )

    @staticmethod
    def _normalize_usage(
        declared: set[str], entries: list[DependencyUsageEntry]
    ) -> dict[str, DependencyUsage]:
        """Reduce the model's per-dependency verdicts to a complete dict
        keyed by every declared dependency id.

        The schema is permissive on purpose (a model slip must not lose an
        otherwise-good prompt to the executor's fault path), so the node
        validates here instead: an undeclared/hallucinated id is dropped
        with a warning; a declared id the model skipped defaults to
        ``REFERENCE`` — the documented cheap/safe default, and it is still
        listed in the prompt text so reference is honoured anyway; on a
        duplicate id, last write wins.
        """
        usage: dict[str, DependencyUsage] = {}
        for entry in entries:
            if entry.dependency not in declared:
                logger.warning(
                    "dependency-usage verdict for undeclared id %r — "
                    "dropping (declared: %s)",
                    entry.dependency,
                    sorted(declared),
                )
                continue
            if entry.dependency in usage:
                logger.warning(
                    "duplicate dependency-usage verdict for %r — last wins",
                    entry.dependency,
                )
            usage[entry.dependency] = entry.usage
        for dep_id in declared:
            if dep_id not in usage:
                logger.warning(
                    "no dependency-usage verdict for declared %r — "
                    "defaulting to REFERENCE",
                    dep_id,
                )
                usage[dep_id] = DependencyUsage.REFERENCE
        return usage

    async def _build_prompt(
        self,
        palette: Any,
        image_deps: dict[str, ImageOutput],
        *,
        model: str = IMAGE_PROMPT_MODEL,
    ) -> tuple[str, dict[str, DependencyUsage] | None]:
        """Brief + slot + palette (+ related-asset block) →
        ``(prompt, usage)``.

        The dependency block — the visual-continuity rules, the
        reference/direct decision rules, and the per-dependency listing —
        is a separate prompt fragment injected ONLY when the slot has
        image dependencies; otherwise nothing about dependencies reaches
        the model and ``usage`` is ``None``. The one structured call
        returns both the prompt and a per-dependency verdict, normalised
        against the slot's declared ``depends_on``."""
        template = IMAGE_PROMPT_PATH.read_text(encoding="utf-8")
        design = self._run_ctx.cust.design_direction
        dark_mode = self._run_ctx.cust.colors_direction.dark_mode
        palette_summary = "\n".join(
            f"  {slot_id}: {color.oklch} — {color.display_name}: {color.description}"
            for slot_id, color in palette.colors.items()
        )
        if image_deps:
            listing = "\n".join(
                f"  {dep_id}: {out.prompt}"
                for dep_id, out in image_deps.items()
            )
            fragment = DEP_BLOCK_PATH.read_text(encoding="utf-8")
            dependency_block = Template(fragment).safe_substitute(
                dependencies=listing
            )
        else:
            dependency_block = ""
        prompt = Template(template).safe_substitute(
            name=design.name,
            short=design.short_desc,
            long=design.long_desc,
            palette=palette_summary,
            theme_background=(THEME_BG_DARK if dark_mode else THEME_BG_LIGHT),
            subject=self._slot.description,
            dependency_block=dependency_block,
        )
        result = await self._llm.complete_structured(
            [{"role": "user", "content": prompt}],
            schema=ImagePrompt,
            model=model,
        )
        if not image_deps:
            return result.prompt, None
        usage = self._normalize_usage(
            set(self._slot.depends_on), result.dependency_usage
        )
        return result.prompt, usage

    async def _generate(
        self,
        prompt: str,
        quality: str,
        direct_deps: dict[str, ImageOutput],
    ) -> Path:
        """Generate the raw image (subject on a plain solid background).

        With no DIRECT dependency this is text-to-image. With one or more
        DIRECT dependencies the dependency image(s) themselves are fed to
        the generator — image-conditioned generation via ``compose``,
        using the same generation model — because a DIRECT verdict means
        words alone are not faithful enough. A DIRECT dependency whose
        image file is missing fails fast *before* the retry loop: it will
        not appear between attempts, and silently degrading to
        text-to-image would produce the wrong image.

        The image provider's moderation/infra is non-deterministic — a
        benign prompt can hit a false-positive block, a transient failure,
        or a timeout on one call and succeed on the next — so generation is
        retried a bounded number of times. Unlike background removal there
        is no usable fallback for a missing image, so exhaustion re-raises
        the last provider error and fails the run.
        """
        dest = self._run_ctx.image_dir / f"{self._slot.id}{RAW_SUFFIX}"
        srcs: list[Path] = []
        for dep_id, out in direct_deps.items():
            src = Path(str(out.path))
            if not src.exists():
                raise ProviderError(
                    f"DIRECT dependency {dep_id!r} image missing for "
                    f"{self._slot.id}: {src}"
                )
            srcs.append(src)
        last_error: ProviderError | None = None
        for attempt in range(IMAGE_GEN_MAX_ATTEMPTS):
            try:
                if srcs:
                    await self._image_gen.compose(
                        prompt,
                        srcs,
                        dest,
                        model=IMAGE_GEN_MODEL,
                        quality=quality,
                    )
                else:
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
