"""ModuleRegistry — builds the run's node graph from the run context.

Emits one ``ColorNode``, one ``FontNode``, optionally a ``TextNode``,
``IconNode`` and ``CategoryNode``, plus one ``ImageNode`` per image slot.
Each image node is assigned its dependency keys (``color`` is automatic;
declared ``depends_on`` images are added). The colour, font, text, icon and
classification nodes are level-0 siblings — they all spring from the brand
brief and none depend on the others. The executor levels and runs them.

The three optional roots are built only when the app declares the matching
inventory: ``TextNode`` needs at least one text slot, ``IconNode`` at least
one icon slot, and ``CategoryNode`` a non-empty ``categories`` vocabulary. An
app with no copy overrides / no icon overrides / no classification concept
just has no such root in its graph, and the assembled ``Output`` falls back to
an empty ``TextSet`` / ``IconSet`` / a ``None`` ``category``.
"""

from __future__ import annotations

import logging

from pydantic import BaseModel, ConfigDict

from src.core.run_context import RunContext
from src.modules.base import DependencyKind
from src.modules.categories.category_node import (
    CATEGORY_SLOT_ID,
    CategoryNode,
)
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
    text / icon / classification roots, plus one node per image slot.

    A transport container only (nodes are plain classes, hence
    ``arbitrary_types_allowed``); the executor builds the DAG from each
    node's ``key``/``deps``. ``text``, ``icon`` and ``category`` are ``None``
    when the app declares no text slots / no icon slots / no ``categories``
    vocabulary — the registry skips constructing those nodes so a run doesn't
    burn LLM calls on nothing.
    """

    model_config = ConfigDict(arbitrary_types_allowed=True)

    color: ColorNode
    font: FontNode
    text: TextNode | None
    icon: IconNode | None
    category: CategoryNode | None
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
        seed: dict[str, BaseModel] | None = None,
    ) -> Graph:
        """Construct the colour node, the font node, the optional text /
        icon / classification nodes, and one image node per slot.

        The complexity classifier and background pass are internal
        sub-services every image node shares (one image resolved end to end
        stays the atomic unit). Each image node gets ``color`` as an automatic
        dependency plus its declared ``depends_on`` images (always used as
        reference, folded into the prompt text). The font, text, icon and
        classification nodes are level-0 siblings of the colour node — no node
        depends on any of them today, but the executor still levels them
        alongside colour and runs them concurrently.

        The run's steering rides on ``run_ctx`` (``run_ctx.overwrite_specs`` —
        stamped onto whatever each node re-makes); ``seed`` maps slot id →
        that slot's saved per-item output (a reopen-time regeneration; see the
        ``regen`` / ``expand`` scripts). Each node reads the steering off the
        context and receives the seeded outputs for the slots it owns, and
        re-makes any of its declared slots absent from that seed. An empty seed
        ⇒ a fresh full run that builds every node exactly as before.
        """
        sd = seed or {}

        def _seed(slot_ids: set[str]) -> dict[str, BaseModel]:
            """The slot-level seed scoped to one node's slots."""
            return {sid: sd[sid] for sid in slot_ids if sid in sd}

        color_ids = {s.id for s in self._run_ctx.app.colors}
        color = ColorNode(
            self._run_ctx,
            llm=llm,
            seed=_seed(color_ids),  # type: ignore[arg-type]
        )
        font_ids = {s.id for s in self._run_ctx.app.fonts}
        font = FontNode(
            self._run_ctx,
            llm=llm,
            catalog=google_fonts,
            seed=_seed(font_ids),  # type: ignore[arg-type]
        )
        # No text slots → no text node → no LLM call (and an empty
        # ``text_set`` in the assembled Output, which is also the honest
        # answer when every slot's retry budget exhausts).
        text_ids = {s.id for s in self._run_ctx.app.texts}
        text = (
            TextNode(
                self._run_ctx,
                llm=llm,
                seed=_seed(text_ids),  # type: ignore[arg-type]
            )
            if self._run_ctx.app.texts
            else None
        )
        # No icon slots → no icon node → no LLM calls (the icon module's
        # three calls + any Recraft generation). The orchestrator filters
        # a None icon out of the level-0 sibling set and ``icon_set``
        # defaults to empty on the assembled Output.
        icon_ids = {s.id for s in self._run_ctx.app.icons}
        icon = (
            IconNode(
                self._run_ctx,
                llm=llm,
                catalog=icon_catalog,
                generator=icon_generator,
                seed=_seed(icon_ids),  # type: ignore[arg-type]
            )
            if self._run_ctx.app.icons
            else None
        )
        # No declared vocabulary → no classification node → no LLM call, and
        # a ``None`` category on the assembled Output. An app with no
        # classification concept keeps working exactly as before; the styles
        # API skips the vocabulary check for such an app too.
        category = (
            CategoryNode(
                self._run_ctx,
                llm=llm,
                seed=_seed({CATEGORY_SLOT_ID}),  # type: ignore[arg-type]
            )
            if self._run_ctx.app.categories
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
                seed=_seed({slot.id}),  # type: ignore[arg-type]
            )
            for slot in self._run_ctx.app.images
        ]
        logger.debug(
            "graph: color=%s, font=%s, text=%s, icon=%s, category=%s, "
            "images=%d",
            color.key,
            font.key,
            text.key if text is not None else None,
            icon.key if icon is not None else None,
            category.key if category is not None else None,
            len(images),
        )
        return Graph(
            color=color,
            font=font,
            text=text,
            icon=icon,
            category=category,
            images=images,
        )
