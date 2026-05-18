"""Pipeline — builds the services, runs the steps, assembles the output."""

from __future__ import annotations

import logging

from schema import ImageOutput, Output
from src.core.run_context import RunContext
from src.executor.registry import ModuleRegistry
from src.shared.services.background_remover import PhotoRoomBackgroundRemover
from src.shared.services.litellm_image_generator import LiteLLMImageGenerator
from src.shared.services.llm_client import LiteLLMClient

logger = logging.getLogger(__name__)


class Pipeline:
    """Runs one customization end to end (configuration via settings)."""

    async def run(self, run_ctx: RunContext) -> Output:
        """Resolve every slot via the steps and assemble the ``Output``."""

        llm = LiteLLMClient()
        image_gen = LiteLLMImageGenerator()
        bg_remover = PhotoRoomBackgroundRemover()

        steps = ModuleRegistry(run_ctx).build_all(
            llm=llm,
            image_gen=image_gen,
            bg_remover=bg_remover,
        )

        logger.debug("running colour step")
        palette = await steps.color.run()

        # The image module is atomic per image; the executor owns the
        # per-slot loop (sequential for now — modules stay concurrency-free).
        logger.debug("running image step")
        images: dict[str, ImageOutput] = {}
        for slot in run_ctx.app.images:
            images[slot.id] = await steps.images.run(slot, palette)

        return Output(
            app=run_ctx.app.id,
            display_name=run_ctx.app.display_name,
            colors=palette.colors,
            images=images,
        )
