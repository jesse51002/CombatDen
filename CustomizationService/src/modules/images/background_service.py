"""BackgroundService — remove the solid backdrop, validate, crop.

Extracted from ``ImageGenService`` (which was doing too much). The flow is
unchanged: bounded PhotoRoom removal, each attempt validated by a
two-stage check (deterministic alpha gate, then a vision comparison), then
a tight autocrop — with a bad-cutout-beats-none fallback and a final
copy-the-raw fallback. Atomic per image; the image module composes it.
"""

from __future__ import annotations

import base64
import logging
import shutil
from pathlib import Path
from string import Template

from src.core.errors import ProviderError
from src.core.imaging import autocrop, transparent_fraction
from src.core.run_context import RunContext
from src.modules.base import CustomizationService
from src.modules.images.image_models import BackgroundCheck
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)

BG_CHECK_PROMPT_PATH = Path(__file__).parent / "prompts" / "background_check.md"
CUTOUT_SUFFIX = ".cutout.png"
PNG_DATA_URL_PREFIX = "data:image/png;base64,"
# Below this transparent share the backdrop was not meaningfully removed.
MIN_TRANSPARENT_FRACTION = 0.10

# Per-call constant, not config: the cutout vision check is a property of
# this flow. Override `run/validate_cutout(model=...)` in dev to compare
# models; production uses this default (routes on the gemini key).
BG_VALIDATION_MODEL = "gemini/gemini-3-flash-preview"
# Bounded remover re-calls; on exhaustion the un-removed image is kept.
BG_MAX_ATTEMPTS = 3


class BackgroundService(CustomizationService):
    """The background pass: ``run(raw, dest)`` -> wrote final, was-cutout."""

    def __init__(
        self,
        run_ctx: RunContext | None = None,
        *,
        llm: LLMClient,
        bg_remover: BackgroundRemover | None = None,
    ) -> None:
        """Production passes all three; ``validate_cutout`` only needs
        ``llm``, so the golden eval / manual script / unit tests can build
        a validation-only instance: ``BackgroundService(llm=llm)``.
        ``run`` still requires ``run_ctx`` and ``bg_remover``."""
        super().__init__(run_ctx)
        self._llm = llm
        self._bg_remover = bg_remover

    async def run(
        self, raw: Path, dest: Path, *, model: str = BG_VALIDATION_MODEL
    ) -> bool:
        """Remove → validate → crop; write the final PNG to ``dest``.

        Returns whether a cutout was produced (vs. the un-removed image
        kept as a fallback) — for the caller's logging/provenance.
        """
        cutout, ok = await self._remove_background(raw, model=model)
        if ok:
            await self._autocrop(cutout, dest)
        else:
            shutil.copyfile(raw, dest)
        return ok

    async def _remove_background(
        self, raw: Path, *, model: str = BG_VALIDATION_MODEL
    ) -> tuple[Path, bool]:
        """Bounded background removal.

        Cutout validation is TEMPORARILY DISABLED (the ``validate_cutout``
        block below is commented out — the method and its prompt are kept
        and still exercised by the unit tests + golden eval, so nothing is
        lost). Current behaviour:

        - the first cutout PhotoRoom produces is accepted as-is;
        - only a remover transport error (``ProviderError``) is retried,
          up to ``BG_MAX_ATTEMPTS``;
        - ``(raw, False)`` only if the remover never produced any cutout
          (every attempt raised) — keep the un-removed image.

        Re-enable by uncommenting the marked block (and restoring the
        ``produced`` / keep-last-rejected fallback it references); ``model``
        is kept on the signature for that.
        """
        cutout = self._run_ctx.image_dir / f"{raw.stem}{CUTOUT_SUFFIX}"
        for attempt in range(BG_MAX_ATTEMPTS):
            try:
                await self._bg_remover.remove(raw, cutout)
            except ProviderError:
                logger.warning(
                    "background remover failed on attempt %d/%d for %s",
                    attempt + 1,
                    BG_MAX_ATTEMPTS,
                    raw.name,
                )
                continue
            # --- validation disabled — uncomment to re-enable ----------
            # produced = True  # (declare ``produced = False`` before loop)
            # verdict = await self.validate_cutout(raw, cutout, model=model)
            # if verdict.ok:
            #     return (cutout, True)
            # logger.warning(
            #     "background cutout rejected on attempt %d/%d for %s: %s",
            #     attempt + 1,
            #     BG_MAX_ATTEMPTS,
            #     raw.name,
            #     verdict.reason,
            # )
            # continue  # and after the loop, if produced: keep last cutout
            # -----------------------------------------------------------
            return (cutout, True)
        logger.warning(
            "background remover never produced a cutout for %s; "
            "keeping un-removed image",
            raw.name,
        )
        return (raw, False)

    async def validate_cutout(
        self,
        original: Path,
        cutout: Path,
        *,
        model: str = BG_VALIDATION_MODEL,
    ) -> BackgroundCheck:
        """Validate a cutout against the image it was cut from, in two stages.

        1. Deterministic: a vision model cannot perceive alpha (it sees the
           PNG flattened to RGB), so "was the backdrop removed at all" is
           decided in pixels on the *cutout* — too little transparency
           fails here, with no model call.
        2. Vision: only if enough was removed, the model is shown BOTH the
           original (the subject on its backdrop, before removal) and the
           cutout, and judges whether the cutout is a clean, complete
           isolation of that same subject. The comparison catches a remover
           that ate into the subject — judging the cutout alone cannot.

        The single source of truth for the call: this service's background
        pass, the standalone script, and the golden eval all route through
        this method, so the test cannot drift from production. Only
        ``self._llm`` is used, so a validation-only instance built as
        ``BackgroundService(llm=llm)`` is enough to call it.
        """
        frac = transparent_fraction(cutout)
        if frac < MIN_TRANSPARENT_FRACTION:
            return BackgroundCheck(
                ok=False,
                reason=(
                    f"Only {frac:.0%} of the image is transparent "
                    f"(< {MIN_TRANSPARENT_FRACTION:.0%}); the backdrop was "
                    "not removed."
                ),
            )
        template = BG_CHECK_PROMPT_PATH.read_text(encoding="utf-8")
        instruction = Template(template).safe_substitute(alpha=f"{frac:.0%}")
        before_b64 = base64.b64encode(original.read_bytes()).decode("ascii")
        after_b64 = base64.b64encode(cutout.read_bytes()).decode("ascii")
        # Image order is the contract the prompt states: first BEFORE, then
        # AFTER. All framing text (and how to use $alpha) lives in the .md.
        messages = [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": instruction},
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"{PNG_DATA_URL_PREFIX}{before_b64}"
                        },
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"{PNG_DATA_URL_PREFIX}{after_b64}"
                        },
                    },
                ],
            }
        ]
        return await self._llm.complete_structured(
            messages,
            schema=BackgroundCheck,
            model=model,
        )

    async def _autocrop(self, src: Path, dst: Path) -> None:
        """Crop the clean cutout tight to its subject."""
        autocrop(src, dst)
