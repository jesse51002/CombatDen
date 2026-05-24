"""ModuleRegistry — builds the run's node graph from the run context.

Emits one ``ColorNode``, one ``FontNode``, optionally one ``TextNode``,
plus one ``ImageNode`` per image slot. Each image node is assigned its
dependency keys (``color`` is automatic; declared ``depends_on`` images
are added). The text, font, and colour nodes are level-0 siblings —
all three spring from the brand brief and none depend on the others.
The executor levels and runs them. ``TextNode`` is only built when the
app declares at least one text slot; an app with no copy overrides
just has no text root in its graph, and ``text_set`` defaults to an
empty ``TextSet`` on the assembled ``Output``.
"""

from __future__ import annotations

import logging

from pydantic import BaseModel, ConfigDict

from src.core.run_context import RunContext
from src.modules.base import DependencyKind
from src.modules.colors.color_node import ColorNode
from src.modules.fonts.font_node import FontNode
from src.modules.icons.icon_node import IconNode
from src.modules.images.background_service import BackgroundService
from src.modules.images.complexity_service import ComplexityClassifier
from src.modules.images.image_node import ImageNode
from src.modules.texts.text_node import TextNode
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.google_fonts_catalog import GoogleFontsCatalog
from src.shared.interfaces.icon_set_catalog import IconSetCatalog
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient

logger = logging.getLogger(__name__)


class Graph(BaseModel):
    """The run's node set: the colour root, the font root, the optional
    text and icon roots, plus one node per image slot.

    A transport container only (nodes are plain classes, hence
    ``arbitrary_types_allowed``); the executor builds the DAG from each
    node's ``key``/``deps``. ``text`` and ``icon`` are ``None`` when the
    app declares no text / icon slots — the registry skips constructing
    those nodes so an empty-slots run doesn't burn LLM calls on nothing.
    """

    model_config = ConfigDict(arbitrary_types_allowed=True)

    color: ColorNode
    font: FontNode
    text: TextNode | None
    icon: IconNode | None
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
        google_fonts: GoogleFontsCatalog,
        icon_catalog: IconSetCatalog,
        icon_generator: ImageGenerator,
    ) -> Graph:
        """Construct the colour node, the font node, and one image node
        per slot.

        The classifier and background pass are internal sub-services
        every image node shares (one image resolved end to end stays the
        atomic unit). Each image node gets ``color`` as an automatic
        dependency plus its declared ``depends_on`` images (always used
        as reference, folded into the prompt text). The font node is a
        level-0 sibling of the colour node — no node depends on it
        today, but the executor still levels it alongside colour and
        runs them concurrently.
        """
        color = ColorNode(self._run_ctx, llm=llm)
        font = FontNode(self._run_ctx, llm=llm, catalog=google_fonts)
        # No text slots → no text node → no LLM call (and an empty
        # ``text_set`` in the assembled Output, which is also the honest
        # answer when every slot's retry budget exhausts).
        text = (
            TextNode(self._run_ctx, llm=llm)
            if self._run_ctx.app.texts
            else None
        )
        # No icon slots → no icon node → no LLM calls (the icon module's
        # three calls + any Recraft generation). The orchestrator filters
        # a None icon out of the level-0 sibling set and ``icon_set``
        # defaults to empty on the assembled Output.
        icon = (
            IconNode(
                self._run_ctx,
                llm=llm,
                catalog=icon_catalog,
                generator=icon_generator,
            )
            if self._run_ctx.app.icons
            else None
        )
        classifier = ComplexityClassifier(llm=llm)
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
                background=background,
            )
            for slot in self._run_ctx.app.images
        ]
        logger.debug(
            "graph: color=%s, font=%s, text=%s, icon=%s, images=%d",
            color.key,
            font.key,
            text.key if text is not None else None,
            icon.key if icon is not None else None,
            len(images),
        )
        return Graph(
            color=color, font=font, text=text, icon=icon, images=images
        )
