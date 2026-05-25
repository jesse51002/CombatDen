"""Pipeline — the DAG executor: build the graph, run each level, assemble.

Replaces the old sequential per-slot loop. Nodes are levelled
topologically (networkx); the nodes in a level run concurrently behind a
single run-wide semaphore that caps in-flight modules at
``MAX_CONCURRENT_MODULES`` — the work is I/O-bound but image providers
rate-limit hard, so a level is not unleashed unbounded. Fault-tolerant:
a node failure never aborts the run — only its
transitive dependents are skipped, and whatever resolved is written. The
paid services are returned alongside the output so the writer can total
their running cost.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass

import networkx as nx
from pydantic import BaseModel

from schema import (
    ColorPalette,
    FontSet,
    IconSet,
    ImageSet,
    LottieSet,
    Output,
    OverwriteSpecs,
    TextSet,
)
from src.core.config import settings
from src.core.errors import GraphError
from src.core.run_context import RunContext
from src.executor.registry import Graph, ModuleRegistry
from src.modules.base import DependencyKind, Node
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.google_fonts_catalog import GoogleFontsCatalog
from src.shared.interfaces.icon_set_catalog import IconSetCatalog
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient
from src.shared.services.background_remover import PhotoRoomBackgroundRemover
from src.shared.services.google_fonts_catalog import HttpxGoogleFontsCatalog
from src.shared.services.litellm_image_generator import LiteLLMImageGenerator
from src.shared.services.llm_client import LiteLLMClient
from src.shared.services.local_icon_set_catalog import LocalIconSetCatalog
from src.shared.services.recraft_icon_generator import RecraftIconGenerator

logger = logging.getLogger(__name__)

# Most modules allowed in flight at once. The work is I/O-bound, but
# image providers rate-limit hard — an unbounded level can stampede
# them. One semaphore for the whole run caps concurrency here; levels
# stay sequential regardless.
MAX_CONCURRENT_MODULES = 5


@dataclass(frozen=True)
class PipelineResult:
    """One run's assembled output plus the paid services that produced it.

    The services carry their own running ``cost``; the writer reads them
    to aggregate the run total. A dataclass (not a Pydantic model) so it
    holds the live service instances without per-field isinstance
    enforcement.

    ``generated`` is the set of slot ids this pass actually (re)made — the
    union of each node's ``regenerated``. For a full run that is every slot;
    for a reopen pass it is only the dirty (steered or missing) slots, the
    rest being returned from the seed untouched. Because the paid services are
    freshly constructed per ``run()``, their accumulated cost is exactly the
    spend for ``generated`` — what the expand/regen writer records in
    ``expansion_cost.yaml``.
    """

    output: Output
    llm: LLMClient
    image_gen: ImageGenerator
    bg_remover: BackgroundRemover
    icon_gen: ImageGenerator
    generated: frozenset[str]


class Pipeline:
    """Runs one customization end to end (configuration via settings)."""

    @staticmethod
    def _build_digraph(node_set: Graph) -> nx.DiGraph:
        """Assemble + validate the dependency DiGraph (fail fast, no spend).

        Edges run dependency → dependent. Raises ``GraphError`` if a node
        depends on a key no node produces, or if the edges form a cycle —
        both *before* any node runs.
        """
        graph: nx.DiGraph = nx.DiGraph()
        # ``text`` is optional: apps with no copy overrides don't get a
        # text node, so it's filtered out of the level-0 sibling set
        # rather than producing a no-op root.
        nodes = [
            node_set.color,
            node_set.font,
            *node_set.images,
            *node_set.lotties,
        ]
        if node_set.text is not None:
            nodes.append(node_set.text)
        if node_set.icon is not None:
            nodes.append(node_set.icon)
        for node in nodes:
            graph.add_node(node.key, node=node)
        known = {node.key for node in nodes}
        for node in nodes:
            for dep in node.deps:
                if dep not in known:
                    raise GraphError(
                        f"node {node.key!r} depends on {dep!r} "
                        "which no node produces"
                    )
                graph.add_edge(dep, node.key)
        if not nx.is_directed_acyclic_graph(graph):
            raise GraphError(f"dependency cycle: {nx.find_cycle(graph)}")
        return graph

    @staticmethod
    async def _run_capped(
        node: Node, sem: asyncio.Semaphore
    ) -> BaseModel:
        """Run one node while holding ``sem`` — bounds level concurrency
        to ``MAX_CONCURRENT_MODULES`` without any module change."""
        async with sem:
            return await node.run()

    async def run(
        self,
        run_ctx: RunContext,
        *,
        seed: dict[str, BaseModel] | None = None,
        overwrite_specs: OverwriteSpecs | None = None,
    ) -> PipelineResult:
        """Resolve every node level-by-level, assemble the ``Output``, and
        return it alongside the paid services so the writer can total
        their cost.

        Reopen-time regeneration is entirely a node concern; the executor
        stays domain-blind. ``seed`` (slot id → that slot's saved per-item
        output) is the sole control of what's re-made — a node regenerates any
        declared slot absent from its seed slice and returns the rest verbatim
        (no LLM/provider spend). ``overwrite_specs`` is the call's single
        steering string, stamped onto whatever is re-made. An empty ``seed``
        ⇒ every node regenerates every slot, a normal full run.
        ``PipelineResult.generated`` is the union of the slot ids the nodes
        actually re-made."""
        llm = LiteLLMClient()
        image_gen = LiteLLMImageGenerator()
        bg_remover = PhotoRoomBackgroundRemover()
        icon_gen = RecraftIconGenerator()
        google_fonts: GoogleFontsCatalog = HttpxGoogleFontsCatalog(
            api_key=settings.google_fonts_api_key,
            api_url=settings.google_fonts_api_url,
            ttl_seconds=settings.google_fonts_ttl_seconds,
            request_timeout_seconds=settings.google_fonts_request_timeout_seconds,
        )
        icon_catalog: IconSetCatalog = LocalIconSetCatalog(
            root=settings.icon_sets_dir
        )

        node_set = ModuleRegistry(run_ctx).build_all(
            llm=llm,
            image_gen=image_gen,
            bg_remover=bg_remover,
            google_fonts=google_fonts,
            icon_catalog=icon_catalog,
            icon_generator=icon_gen,
            overwrite_specs=overwrite_specs,
            seed=seed,
        )
        graph = self._build_digraph(node_set)

        resolved: dict[str, BaseModel] = {}
        generated: set[str] = set()
        skipped: set[str] = set()
        sem = asyncio.Semaphore(MAX_CONCURRENT_MODULES)

        for generation in nx.topological_generations(graph):
            batch = [
                graph.nodes[key]["node"]
                for key in generation
                if key not in skipped
            ]
            if not batch:
                continue
            # Inject each node's available dependency outputs. A node that is
            # only assembling from its seed needs none; one that regenerates
            # reads them — and was skipped above if a dependency it needs
            # failed, so injecting just what resolved is safe.
            for node in batch:
                node.inputs = {
                    dep: resolved[dep]
                    for dep in node.deps
                    if dep in resolved
                }
            logger.debug(
                "running level: %s", [node.key for node in batch]
            )
            results = await asyncio.gather(
                *(self._run_capped(node, sem) for node in batch),
                return_exceptions=True,
            )
            for node, result in zip(batch, results):
                if isinstance(result, Exception):
                    # One bad node must not lose finished work. Skip only the
                    # dependents that would actually REGENERATE (they need the
                    # failed output); a dependent that is merely reassembling
                    # its seed needs nothing and still runs.
                    logger.warning(
                        "node %s failed (%s); skipping its regenerating "
                        "dependents",
                        node.key,
                        result,
                    )
                    skipped |= {
                        dep
                        for dep in nx.descendants(graph, node.key)
                        if graph.nodes[dep]["node"].dirty()
                    } | {node.key}
                else:
                    resolved[node.key] = result
                    generated |= node.regenerated

        output = self._assemble(run_ctx, resolved)
        return PipelineResult(
            output=output,
            llm=llm,
            image_gen=image_gen,
            bg_remover=bg_remover,
            icon_gen=icon_gen,
            generated=frozenset(generated),
        )

    @staticmethod
    def _assemble(
        run_ctx: RunContext, resolved: dict[str, BaseModel]
    ) -> Output:
        """Assemble the (possibly partial) ``Output`` from what resolved."""
        palette = resolved.get(DependencyKind.COLOR.value)
        if palette is None:
            # Colour node didn't resolve — emit the minimal valid shell so
            # the writer can still produce something useful. `palette` is
            # required by ColorPalette, but there's nothing to populate it
            # with when colours failed; an empty dict is the honest answer.
            palette = ColorPalette(
                mode=run_ctx.cust.colors_direction.mode,
                colors={},
                palette={},
            )
        if not palette.colors:
            logger.error(
                "colour node did not resolve — output has no colours "
                "(and therefore no images)"
            )
        font_set = resolved.get(DependencyKind.FONT.value)
        if font_set is None:
            # Font node didn't resolve — empty FontSet is the honest
            # answer (no font slots populated). Unlike colours, no other
            # node depends on it, so an empty set doesn't cascade.
            font_set = FontSet(fonts={})
            logger.error("font node did not resolve — output has no fonts")
        text_set = resolved.get(DependencyKind.TEXT.value)
        if text_set is None:
            # Text node either wasn't built (app declared no text slots —
            # the registry skipped it) or failed outright. Empty TextSet
            # is the honest answer either way; the MobileApp falls back
            # to its bundled default copy. Logging the failure is only
            # warranted when a text node was actually expected — the
            # registry skip is a normal, common case for apps without
            # copy overrides.
            text_set = TextSet(texts={})
            if run_ctx.app.texts:
                logger.error(
                    "text node did not resolve — output has no copy "
                    "overrides"
                )
        icon_set = resolved.get(DependencyKind.ICON.value)
        if icon_set is None:
            # Icon node either wasn't built (app declared no icon slots —
            # the registry skipped it) or failed outright. Empty IconSet
            # is the honest answer either way; the MobileApp falls back to
            # its bundled icons. Only log a failure when an icon node was
            # actually expected (the registry skip is the normal case for
            # apps without icon overrides).
            icon_set = IconSet(icons={})
            if run_ctx.app.icons:
                logger.error(
                    "icon node did not resolve — output has no icon "
                    "overrides"
                )
        image_set = ImageSet(
            images={
                slot.id: resolved[slot.id]
                for slot in run_ctx.app.images
                if slot.id in resolved
            }
        )
        # Each lottie node that resolved contributes its slot; a slot whose
        # COLOR dep failed (or, for a reveal, whose image failed) was
        # skipped and is simply absent — the honest partial answer, same as
        # images.
        lottie_set = LottieSet(
            lotties={
                slot.id: resolved[slot.id]
                for slot in run_ctx.app.lotties
                if slot.id in resolved
            }
        )
        return Output(
            app=run_ctx.app.id,
            display_name=run_ctx.app.display_name,
            design_name=run_ctx.cust.design_direction.name,
            image_set=image_set,
            color_set=palette,
            font_set=font_set,
            text_set=text_set,
            icon_set=icon_set,
            lottie_set=lottie_set,
        )
