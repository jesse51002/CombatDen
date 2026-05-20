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

from schema import ColorPalette, ImageSet, Output
from src.core.errors import GraphError
from src.core.run_context import RunContext
from src.executor.registry import Graph, ModuleRegistry
from src.modules.base import DependencyKind, Node
from src.shared.interfaces.background_remover import BackgroundRemover
from src.shared.interfaces.image_generator import ImageGenerator
from src.shared.interfaces.llm_client import LLMClient
from src.shared.services.background_remover import PhotoRoomBackgroundRemover
from src.shared.services.litellm_image_generator import LiteLLMImageGenerator
from src.shared.services.llm_client import LiteLLMClient

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
    """

    output: Output
    llm: LLMClient
    image_gen: ImageGenerator
    bg_remover: BackgroundRemover


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
        nodes = [node_set.color, *node_set.images]
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

    async def run(self, run_ctx: RunContext) -> PipelineResult:
        """Resolve every node level-by-level, assemble the ``Output``, and
        return it alongside the paid services so the writer can total
        their cost."""
        llm = LiteLLMClient()
        image_gen = LiteLLMImageGenerator()
        bg_remover = PhotoRoomBackgroundRemover()

        node_set = ModuleRegistry(run_ctx).build_all(
            llm=llm,
            image_gen=image_gen,
            bg_remover=bg_remover,
        )
        graph = self._build_digraph(node_set)

        resolved: dict[str, BaseModel] = {}
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
            # The executor injects each node's resolved dependency outputs
            # just before running it (each node runs exactly once).
            for node in batch:
                node.inputs = {dep: resolved[dep] for dep in node.deps}
            logger.debug(
                "running level: %s", [node.key for node in batch]
            )
            results = await asyncio.gather(
                *(self._run_capped(node, sem) for node in batch),
                return_exceptions=True,
            )
            for node, result in zip(batch, results):
                if isinstance(result, Exception):
                    # One bad node must not lose finished work: skip only
                    # its transitive dependents, keep the rest.
                    logger.warning(
                        "node %s failed (%s); skipping its dependents",
                        node.key,
                        result,
                    )
                    skipped |= set(
                        nx.descendants(graph, node.key)
                    ) | {node.key}
                else:
                    resolved[node.key] = result

        output = self._assemble(run_ctx, resolved)
        return PipelineResult(
            output=output,
            llm=llm,
            image_gen=image_gen,
            bg_remover=bg_remover,
        )

    @staticmethod
    def _assemble(
        run_ctx: RunContext, resolved: dict[str, BaseModel]
    ) -> Output:
        """Assemble the (possibly partial) ``Output`` from what resolved."""
        palette = resolved.get(DependencyKind.COLOR.value)
        if palette is None:
            palette = ColorPalette(
                mode=run_ctx.cust.colors_direction.mode, colors={}
            )
        if not palette.colors:
            logger.error(
                "colour node did not resolve — output has no colours "
                "(and therefore no images)"
            )
        image_set = ImageSet(
            images={
                slot.id: resolved[slot.id]
                for slot in run_ctx.app.images
                if slot.id in resolved
            }
        )
        return Output(
            app=run_ctx.app.id,
            display_name=run_ctx.app.display_name,
            image_set=image_set,
            color_set=palette,
        )
