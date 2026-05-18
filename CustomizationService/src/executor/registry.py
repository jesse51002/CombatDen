"""ModuleRegistry — constructs the customization modules (services) for one run."""

from __future__ import annotations

import logging

from pydantic import BaseModel, ConfigDict

from src.core.run_context import RunContext
from src.modules.colors.color_service import ColorGenService
from src.modules.images.background_service import BackgroundService
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_service import ImageGenService
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)


class Steps(BaseModel):
    """The run's services: the colour root plus the ones that depend on it."""

    model_config = ConfigDict(arbitrary_types_allowed=True)

    color: ColorGenService
    images: ImageGenService


class ModuleRegistry:
    """Builds the run's customization services from the run context."""

    def __init__(self, run_ctx: RunContext) -> None:
        self._run_ctx = run_ctx

    def build_all(
        self,
        *,
        llm: LLMClient,
        image_gen: ImageGenerator,
        bg_remover: BackgroundRemover,
    ) -> Steps:
        """Construct the colour service and the colour-dependent services.

        The classifier and background pass are internal deps of the image
        module (one image resolved end to end stays the atomic unit), so
        ``Steps`` still exposes only ``color`` + ``images``.
        """
        color = ColorGenService(self._run_ctx, llm=llm)
        classifier = ComplexityClassifier(self._run_ctx, llm=llm)
        background = BackgroundService(
            self._run_ctx, llm=llm, bg_remover=bg_remover
        )
        images = ImageGenService(
            self._run_ctx,
            llm=llm,
            image_gen=image_gen,
            classifier=classifier,
            background=background,
        )
        logger.debug(
            "services: color=%s, images=%s",
            type(color).__name__,
            type(images).__name__,
        )
        return Steps(color=color, images=images)
