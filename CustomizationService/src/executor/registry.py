"""ModuleRegistry — builds the run's node graph from the run context.

Emits one ``ColorNode`` plus one ``ImageNode`` per image slot, each
assigned its dependency keys (``color`` is automatic; declared
``depends_on`` images are added). The executor levels and runs them.
"""

from __future__ import annotations

import logging

from pydantic import BaseModel, ConfigDict

from src.core.run_context import RunContext
from src.modules.base import DependencyKind
from src.modules.colors.color_node import ColorNode
from src.modules.images.background_service import BackgroundService
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_node import ImageNode
from src.modules.images.style_service import StyleAdherenceService
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)


class Graph(BaseModel):
    """The run's node set: the colour root plus one node per image slot.

    A transport container only (nodes are plain classes, hence
    ``arbitrary_types_allowed``); the executor builds the DAG from each
    node's ``key``/``deps``.
    """

    model_config = ConfigDict(arbitrary_types_allowed=True)

    color: ColorNode
    images: list[ImageNode]


class ModuleRegistry:
    """Builds the run's node graph from the run context."""

    def __init__(self, run_ctx: RunContext) -> None:
        self._run_ctx = run_ctx

    def build_all(
        self,
        *,
        llm: LLMClient,
        image_gen: ImageGenerator,
        bg_remover: BackgroundRemover,
    ) -> Graph:
        """Construct the colour node and one image node per slot.

        The classifier, style check and background pass are internal
        sub-services every image node shares (one image resolved end to
        end stays the atomic unit). The reference/direct dependency
        verdict is no longer a sub-service — the prompt-writing call
        makes it inline. Each image node gets ``color`` as an automatic
        dependency plus its declared ``depends_on`` images.
        """
        color = ColorNode(self._run_ctx, llm=llm)
        classifier = ComplexityClassifier(llm=llm)
        style = StyleAdherenceService(llm=llm)
        background = BackgroundService(bg_remover=bg_remover)

        images = [
            ImageNode(
                self._run_ctx,
                slot=slot,
                deps=frozenset({DependencyKind.COLOR.value})
                | frozenset(slot.depends_on),
                llm=llm,
                image_gen=image_gen,
                classifier=classifier,
                style=style,
                background=background,
            )
            for slot in self._run_ctx.app.images
        ]
        logger.debug(
            "graph: color=%s, images=%d", color.key, len(images)
        )
        return Graph(color=color, images=images)
